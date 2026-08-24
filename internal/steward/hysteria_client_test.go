package steward

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
)

func TestHysteriaClientAssetMatrix(t *testing.T) {
	expected := map[string]string{
		"darwin/amd64":  "hysteria-darwin-amd64",
		"darwin/arm64":  "hysteria-darwin-arm64",
		"linux/amd64":   "hysteria-linux-amd64",
		"linux/arm64":   "hysteria-linux-arm64",
		"windows/amd64": "hysteria-windows-amd64.exe",
		"windows/arm64": "hysteria-windows-arm64.exe",
	}
	for platform, name := range expected {
		parts := splitPlatform(platform)
		asset, err := platformHysteriaClientAsset(parts[0], parts[1])
		if err != nil {
			t.Fatalf("resolve %s: %v", platform, err)
		}
		if asset.Name != name || len(asset.SHA256) != sha256.Size*2 {
			t.Fatalf("asset metadata for %s is invalid: %#v", platform, asset)
		}
	}
	if _, err := platformHysteriaClientAsset("plan9", "amd64"); err == nil {
		t.Fatal("unsupported Hysteria client platform was accepted")
	}
}

func TestEnsureHysteriaClientDownloadsVerifiesAndCaches(t *testing.T) {
	body := []byte("synthetic-hysteria-binary")
	sum := sha256.Sum256(body)
	asset := hysteriaClientAsset{Name: "hysteria-fixture", SHA256: hex.EncodeToString(sum[:])}
	var requests atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		requests.Add(1)
		if request.URL.Path != "/"+asset.Name {
			http.NotFound(response, request)
			return
		}
		_, _ = response.Write(body)
	}))
	defer server.Close()

	state := &State{PrivateDir: t.TempDir()}
	path, downloaded, err := ensureHysteriaClientFrom(context.Background(), state, server.Client(), server.URL, asset)
	if err != nil {
		t.Fatal(err)
	}
	if !downloaded || requests.Load() != 1 {
		t.Fatalf("first helper resolution did not download exactly once: downloaded=%t requests=%d", downloaded, requests.Load())
	}
	wantDirectory := filepath.Join(state.PrivateDir, "tools", "hysteria", hysteriaClientVersion)
	if filepath.Dir(path) != wantDirectory {
		t.Fatalf("helper escaped private cache: %s", path)
	}
	actual, err := os.ReadFile(path)
	if err != nil || string(actual) != string(body) {
		t.Fatalf("cached helper is wrong: %v", err)
	}

	secondPath, downloaded, err := ensureHysteriaClientFrom(context.Background(), state, server.Client(), server.URL, asset)
	if err != nil {
		t.Fatal(err)
	}
	if downloaded || secondPath != path || requests.Load() != 1 {
		t.Fatal("verified Hysteria client cache was not reused")
	}

	if err := os.WriteFile(path, []byte("corrupt"), 0o700); err != nil {
		t.Fatal(err)
	}
	_, downloaded, err = ensureHysteriaClientFrom(context.Background(), state, server.Client(), server.URL, asset)
	if err != nil {
		t.Fatal(err)
	}
	if !downloaded || requests.Load() != 2 {
		t.Fatal("corrupt Hysteria client cache was not replaced from a verified download")
	}
}

func TestEnsureHysteriaClientRejectsChecksumMismatch(t *testing.T) {
	asset := hysteriaClientAsset{Name: "hysteria-fixture", SHA256: string(make([]byte, sha256.Size*2))}
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
		_, _ = response.Write([]byte("unexpected"))
	}))
	defer server.Close()
	state := &State{PrivateDir: t.TempDir()}
	path, downloaded, err := ensureHysteriaClientFrom(context.Background(), state, server.Client(), server.URL, asset)
	if err == nil || downloaded || path != "" {
		t.Fatal("checksum mismatch did not fail closed")
	}
	target := filepath.Join(state.PrivateDir, "tools", "hysteria", hysteriaClientVersion, asset.Name)
	if _, statErr := os.Stat(target); !os.IsNotExist(statErr) {
		t.Fatal("checksum mismatch left an installed helper")
	}
}

func splitPlatform(platform string) [2]string {
	for index := range platform {
		if platform[index] == '/' {
			return [2]string{platform[:index], platform[index+1:]}
		}
	}
	return [2]string{platform, ""}
}
