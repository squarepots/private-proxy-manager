package steward

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

const (
	hysteriaClientVersion  = "v2.9.3"
	hysteriaReleaseBaseURL = "https://github.com/HyNetworks/hysteria/releases/download/app/" + hysteriaClientVersion
	maxHysteriaBinarySize  = 64 << 20
)

type hysteriaClientAsset struct {
	Name   string
	SHA256 string
}

var hysteriaClientAssets = map[string]hysteriaClientAsset{
	"darwin/amd64":  {Name: "hysteria-darwin-amd64", SHA256: "e90560423f762e6342b875bc477e1f1d33e38e0434b3263a039a319780f314d6"},
	"darwin/arm64":  {Name: "hysteria-darwin-arm64", SHA256: "2cba6474c629debe42c288fd512de54f55415102348a1f8e771d3c6a91b860ef"},
	"linux/amd64":   {Name: "hysteria-linux-amd64", SHA256: "66dbdb0608f25f3057b433afe975a9fc1af2ca8e512479e294988b3ef363d6c1"},
	"linux/arm64":   {Name: "hysteria-linux-arm64", SHA256: "938df06c5a8ed001dbc38718b5385b5fcbd721669f1163518ea8e738866865f2"},
	"windows/amd64": {Name: "hysteria-windows-amd64.exe", SHA256: "bcd3865b09be2e5cc18d117dcf3ad687d1e6e27b0b050376b9cf4ea251b64d6f"},
	"windows/arm64": {Name: "hysteria-windows-arm64.exe", SHA256: "14aad6e421d561139f9f5e2b4c16cec9c08ee1e610d6ea2cf6f2c9737c32af2e"},
}

func platformHysteriaClientAsset(goos, goarch string) (hysteriaClientAsset, error) {
	asset, ok := hysteriaClientAssets[goos+"/"+goarch]
	if !ok {
		return hysteriaClientAsset{}, fmt.Errorf("Hysteria client helper is unsupported on %s/%s", goos, goarch)
	}
	return asset, nil
}

func ensureHysteriaClient(ctx context.Context, state *State) (string, bool, error) {
	asset, err := platformHysteriaClientAsset(runtime.GOOS, runtime.GOARCH)
	if err != nil {
		return "", false, err
	}
	client := &http.Client{Timeout: 2 * time.Minute}
	return ensureHysteriaClientFrom(ctx, state, client, hysteriaReleaseBaseURL, asset)
}

func ensureHysteriaClientFrom(ctx context.Context, state *State, client *http.Client, baseURL string, asset hysteriaClientAsset) (string, bool, error) {
	if state == nil || state.PrivateDir == "" {
		return "", false, errors.New("private state is required for the Hysteria client cache")
	}
	if client == nil {
		return "", false, errors.New("HTTP client is required for the Hysteria client download")
	}
	if asset.Name == "" || filepath.Base(asset.Name) != asset.Name || strings.ContainsAny(asset.Name, `/\\`) {
		return "", false, errors.New("Hysteria client asset name is invalid")
	}
	decodedHash, decodeErr := hex.DecodeString(asset.SHA256)
	if decodeErr != nil || len(decodedHash) != sha256.Size {
		return "", false, errors.New("Hysteria client asset metadata is invalid")
	}
	cacheDir := filepath.Join(state.PrivateDir, "tools", "hysteria", hysteriaClientVersion)
	if err := os.MkdirAll(cacheDir, 0o700); err != nil {
		return "", false, fmt.Errorf("create Hysteria client cache: %w", err)
	}
	if err := protectPath(cacheDir, true); err != nil {
		return "", false, err
	}
	target := filepath.Join(cacheDir, asset.Name)
	valid, err := fileMatchesSHA256(target, asset.SHA256)
	if err != nil {
		return "", false, err
	}
	if valid {
		return target, false, nil
	}

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, strings.TrimRight(baseURL, "/")+"/"+asset.Name, nil)
	if err != nil {
		return "", false, fmt.Errorf("create Hysteria client download request: %w", err)
	}
	response, err := client.Do(request)
	if err != nil {
		return "", false, fmt.Errorf("download Hysteria client: %w", err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return "", false, fmt.Errorf("download Hysteria client: unexpected HTTP status %d", response.StatusCode)
	}
	if response.ContentLength > maxHysteriaBinarySize {
		return "", false, errors.New("download Hysteria client: response exceeds the size limit")
	}

	temporary, err := os.CreateTemp(cacheDir, ".hysteria-download-*")
	if err != nil {
		return "", false, fmt.Errorf("create Hysteria client download: %w", err)
	}
	temporaryPath := temporary.Name()
	removeTemporary := true
	defer func() {
		if removeTemporary {
			_ = os.Remove(temporaryPath)
		}
	}()
	hash := sha256.New()
	written, copyErr := io.Copy(io.MultiWriter(temporary, hash), io.LimitReader(response.Body, maxHysteriaBinarySize+1))
	closeErr := temporary.Close()
	if copyErr != nil {
		return "", false, fmt.Errorf("write Hysteria client download: %w", copyErr)
	}
	if closeErr != nil {
		return "", false, fmt.Errorf("close Hysteria client download: %w", closeErr)
	}
	if written > maxHysteriaBinarySize {
		return "", false, errors.New("download Hysteria client: response exceeds the size limit")
	}
	actual := hex.EncodeToString(hash.Sum(nil))
	if !strings.EqualFold(actual, asset.SHA256) {
		return "", false, errors.New("download Hysteria client: SHA-256 verification failed")
	}
	if err := os.Chmod(temporaryPath, 0o700); err != nil {
		return "", false, fmt.Errorf("make Hysteria client executable: %w", err)
	}
	if err := atomicReplace(temporaryPath, target); err != nil {
		return "", false, fmt.Errorf("install Hysteria client in private cache: %w", err)
	}
	removeTemporary = false
	if err := os.Chmod(target, 0o700); err != nil {
		return "", false, fmt.Errorf("protect Hysteria client executable: %w", err)
	}
	return target, true, nil
}

func fileMatchesSHA256(path, expected string) (bool, error) {
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("inspect cached Hysteria client: %w", err)
	}
	if !info.Mode().IsRegular() {
		return false, errors.New("cached Hysteria client is not a regular file")
	}
	file, err := os.Open(path)
	if err != nil {
		return false, fmt.Errorf("open cached Hysteria client: %w", err)
	}
	defer file.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return false, fmt.Errorf("hash cached Hysteria client: %w", err)
	}
	return strings.EqualFold(hex.EncodeToString(hash.Sum(nil)), expected), nil
}
