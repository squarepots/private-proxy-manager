package steward

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"time"

	workerassets "github.com/squarepots/route-steward/worker"
)

var (
	workerNamePattern              = regexp.MustCompile(`^[a-z0-9][a-z0-9-]{0,62}$`)
	hostNamePattern                = regexp.MustCompile(`^[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$`)
	tokenPattern                   = regexp.MustCompile(`^[A-Za-z0-9_-]{43}$`)
	errSubscriptionPayloadTooLarge = errors.New("subscription-payload-too-large")
)

type subscriptionState struct {
	Schema            int     `json:"schema"`
	WorkerName        string  `json:"worker_name"`
	Host              string  `json:"host"`
	Token             string  `json:"token"`
	PendingToken      *string `json:"pending_token"`
	LastPublishedAt   *string `json:"last_published_at"`
	RotationStartedAt *string `json:"rotation_started_at,omitempty"`
	RotatedAt         *string `json:"rotated_at,omitempty"`
	Reference         string  `json:"-"`
	Path              string  `json:"-"`
	TargetID          string  `json:"-"`
}

func AssertSubscriptionBodySize(body string) (int, error) {
	size := len([]byte(body))
	if size > 5120 {
		return size, errSubscriptionPayloadTooLarge
	}
	return size, nil
}

func newSubscriptionToken() (string, error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(raw), nil
}

func validateWorkerIdentity(workerName, hostName string) (string, error) {
	if !workerNamePattern.MatchString(workerName) {
		return "", errors.New("worker_name must be a valid Cloudflare Worker name")
	}
	host := strings.ToLower(strings.TrimSpace(hostName))
	if !hostNamePattern.MatchString(host) || strings.Contains(host, "..") || strings.HasPrefix(host, ".") || strings.HasSuffix(host, ".") {
		return "", errors.New("host must be one valid HTTPS hostname without scheme or path")
	}
	return host, nil
}

func readSubscriptionState(state *State, targetID string) (*subscriptionState, error) {
	target := findClientTarget(state.Inventory, targetID)
	if target == nil || target.Renderer != "shadowrocket" {
		return nil, fmt.Errorf("ClientTarget %q is not a Shadowrocket target", targetID)
	}
	if target.SubscriptionSecretRef == "" {
		return nil, fmt.Errorf("ClientTarget %q has no private subscription state", targetID)
	}
	path, err := ResolveSecret(target.SubscriptionSecretRef, state.PrivateDir, nil)
	if err != nil {
		return nil, err
	}
	var doc subscriptionState
	if err := readJSON(path, &doc); err != nil {
		return nil, err
	}
	if doc.Schema != 1 || !tokenPattern.MatchString(doc.Token) {
		return nil, errors.New("private subscription state is invalid")
	}
	if doc.PendingToken != nil && !tokenPattern.MatchString(*doc.PendingToken) {
		return nil, errors.New("private subscription pending token is invalid")
	}
	host, err := validateWorkerIdentity(doc.WorkerName, doc.Host)
	if err != nil {
		return nil, err
	}
	doc.Host = host
	doc.Reference = target.SubscriptionSecretRef
	doc.Path = path
	doc.TargetID = targetID
	return &doc, nil
}

func initializeSubscriptionState(state *State, targetID, workerName, hostName string) (*subscriptionState, error) {
	target := findClientTarget(state.Inventory, targetID)
	if target == nil || target.Renderer != "shadowrocket" {
		return nil, fmt.Errorf("ClientTarget %q is not a Shadowrocket target", targetID)
	}
	host, err := validateWorkerIdentity(workerName, hostName)
	if err != nil {
		return nil, err
	}
	for _, other := range state.Inventory.ClientTargets {
		if other.ID == targetID || other.SubscriptionSecretRef == "" {
			continue
		}
		otherState, err := readSubscriptionState(state, other.ID)
		if err != nil {
			return nil, fmt.Errorf("ClientTarget %q has invalid subscription state: %w", other.ID, err)
		}
		if otherState.WorkerName == workerName {
			return nil, fmt.Errorf("Worker %q is already assigned to ClientTarget %q", workerName, other.ID)
		}
		if otherState.Host == host {
			return nil, fmt.Errorf("subscription host %q is already assigned to ClientTarget %q", host, other.ID)
		}
	}
	if target.SubscriptionSecretRef != "" {
		existing, err := readSubscriptionState(state, targetID)
		if err != nil {
			return nil, err
		}
		if existing.WorkerName != workerName || existing.Host != host {
			return nil, errors.New("subscription delivery is already initialized for a different Worker or host")
		}
		return existing, nil
	}
	token, err := newSubscriptionToken()
	if err != nil {
		return nil, err
	}
	reference := "subscription:" + targetID
	relative := filepath.ToSlash(filepath.Join("subscriptions", targetID+".json"))
	path := filepath.Join(state.PrivateDir, "secrets", filepath.FromSlash(relative))
	doc := subscriptionState{Schema: 1, WorkerName: workerName, Host: host, Token: token, PendingToken: nil, LastPublishedAt: nil}
	data, err := json.MarshalIndent(doc, "", "  ")
	if err != nil {
		return nil, err
	}
	candidate := cloneInventory(state.Inventory)
	candidateTarget := findClientTarget(candidate, targetID)
	candidateTarget.SubscriptionSecretRef = reference
	candidateTarget.Delivery = "subscription"
	if err := createRegisteredSecret(state, candidate, reference, "cloudflare-subscription", relative, path, append(data, '\n')); err != nil {
		return nil, err
	}
	return readSubscriptionState(state, targetID)
}

func ExportSubscriptionBody(state *State, targetID string) (string, int, error) {
	target := findClientTarget(state.Inventory, targetID)
	if target == nil || target.Renderer != "shadowrocket" {
		return "", 0, fmt.Errorf("ClientTarget %q is not a Shadowrocket target", targetID)
	}
	profile := findProfile(state.Inventory, target.Profile)
	if profile == nil {
		return "", 0, fmt.Errorf("unknown Profile %q", target.Profile)
	}
	nodes, _, err := profileNodes(state, *profile)
	if err != nil {
		return "", 0, err
	}
	uris := make([]string, 0, len(nodes))
	for _, node := range nodes {
		uri, err := shadowrocketURI(node)
		if err != nil {
			return "", 0, err
		}
		uris = append(uris, uri)
	}
	if len(uris) == 0 {
		return "", 0, errors.New("no Shadowrocket nodes were produced")
	}
	body := base64.StdEncoding.EncodeToString([]byte(strings.Join(uris, "\n")))
	if _, err := AssertSubscriptionBodySize(body); err != nil {
		return "", 0, err
	}
	return body, len(uris), nil
}

func PublishSubscription(state *State, targetID string, context map[string]any) (map[string]any, error) {
	subscription, err := readSubscriptionState(state, targetID)
	if err != nil {
		if stringField(context, "worker_name") == "" || stringField(context, "host") == "" {
			return nil, err
		}
		subscription, err = initializeSubscriptionState(state, targetID, stringField(context, "worker_name"), stringField(context, "host"))
		if err != nil {
			return nil, err
		}
	}
	if subscription.PendingToken != nil {
		return nil, errors.New("a subscription token rotation is pending")
	}
	body, _, err := ExportSubscriptionBody(state, targetID)
	if err != nil {
		return nil, err
	}
	if err := deployWorkerAndVerify(subscription.WorkerName, subscription.Host, subscription.Token, body); err != nil {
		return nil, err
	}
	now := utcNow()
	subscription.LastPublishedAt = &now
	if err := writeJSONAtomic(subscription.Path, subscription); err != nil {
		return nil, err
	}
	if _, err := RenderClients(state, targetID, true); err != nil {
		return nil, fmt.Errorf("subscription published but local import artifact failed: %w", err)
	}
	return map[string]any{"client_target": targetID, "worker": subscription.WorkerName, "published": true, "verified": true}, nil
}

func RotateSubscriptionToken(state *State, targetID string) (map[string]any, error) {
	subscription, err := readSubscriptionState(state, targetID)
	if err != nil {
		return nil, err
	}
	proposed := ""
	if subscription.PendingToken != nil {
		proposed = *subscription.PendingToken
	} else {
		proposed, err = newSubscriptionToken()
		if err != nil {
			return nil, err
		}
		now := utcNow()
		subscription.PendingToken = &proposed
		subscription.RotationStartedAt = &now
		if err := writeJSONAtomic(subscription.Path, subscription); err != nil {
			return nil, err
		}
	}
	body, _, err := ExportSubscriptionBody(state, targetID)
	if err != nil {
		return nil, err
	}
	if err := deployWorkerAndVerify(subscription.WorkerName, subscription.Host, proposed, body); err != nil {
		return nil, err
	}
	var fresh subscriptionState
	if err := readJSON(subscription.Path, &fresh); err != nil {
		return nil, err
	}
	if fresh.PendingToken == nil || *fresh.PendingToken != proposed {
		return nil, errors.New("subscription rotation intent changed during publication")
	}
	now := utcNow()
	fresh.Token = proposed
	fresh.PendingToken = nil
	fresh.RotatedAt = &now
	fresh.LastPublishedAt = &now
	if err := writeJSONAtomic(subscription.Path, &fresh); err != nil {
		return nil, err
	}
	if _, err := RenderClients(state, targetID, true); err != nil {
		return nil, err
	}
	return map[string]any{"client_target": targetID, "token_rotated": true, "published": true, "verified": true, "old_token_revoked_at_worker": true, "unrelated_route_credentials_changed": false, "unrelated_client_credentials_changed": false}, nil
}

func deployWorkerAndVerify(workerName, host, token, body string) error {
	if _, err := AssertSubscriptionBodySize(body); err != nil {
		return err
	}
	stage, err := os.MkdirTemp("", "rst-subscription-*")
	if err != nil {
		return err
	}
	defer os.RemoveAll(stage)
	if err := protectPath(stage, true); err != nil {
		return err
	}
	for _, name := range []string{"package.json", "package-lock.json", "wrangler.jsonc", "tsconfig.json", "src/index.ts"} {
		data, err := fs.ReadFile(workerassets.Files, name)
		if err != nil {
			return err
		}
		path := filepath.Join(stage, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
			return err
		}
		if err := os.WriteFile(path, data, 0o600); err != nil {
			return err
		}
	}
	sum := sha256.Sum256([]byte(token))
	secretPath := filepath.Join(stage, "worker-secrets.json")
	secretData, _ := json.Marshal(map[string]string{"SUBSCRIPTION_TOKEN_HASH": hex.EncodeToString(sum[:]), "SUBSCRIPTION_BODY": body})
	if err := writeFileAtomic(secretPath, secretData, 0o600); err != nil {
		return err
	}
	npm, npx := "npm", "npx"
	if runtime.GOOS == "windows" {
		npm = "npm.cmd"
		npx = "npx.cmd"
	}
	if _, err := exec.LookPath(npm); err != nil {
		return errors.New("npm is unavailable for optional Cloudflare publication")
	}
	if _, err := exec.LookPath(npx); err != nil {
		return errors.New("npx is unavailable for optional Cloudflare publication")
	}
	run := func(executable string, args ...string) error {
		cmd := exec.Command(executable, args...)
		cmd.Dir = stage
		cmd.Env = append(os.Environ(), "WRANGLER_SEND_METRICS=false")
		output, err := cmd.CombinedOutput()
		if err != nil {
			return fmt.Errorf("Cloudflare Worker command failed: %w: %s", err, string(output))
		}
		return nil
	}
	if err := run(npm, "ci", "--ignore-scripts", "--no-audit", "--no-fund"); err != nil {
		return fmt.Errorf("Worker locked install failed: %w", err)
	}
	base := []string{"--no-install", "wrangler", "deploy", "--config", "wrangler.jsonc", "--name", workerName}
	if err := run(npx, append(base, "--dry-run", "--strict")...); err != nil {
		return fmt.Errorf("Worker strict dry-run failed: %w", err)
	}
	if err := run(npx, append(base, "--secrets-file", secretPath, "--keep-vars", "--minify", "--strict")...); err != nil {
		return fmt.Errorf("Cloudflare rejected Worker deployment: %w", err)
	}
	return verifySubscriptionEndpoint("https://"+host+"/s/"+token, body)
}

func verifySubscriptionEndpoint(endpoint, expected string) error {
	client := &http.Client{Timeout: 30 * time.Second}
	request, err := http.NewRequest(http.MethodGet, endpoint, nil)
	if err != nil {
		return err
	}
	request.Header.Set("User-Agent", "RouteSteward/1")
	response, err := client.Do(request)
	if err != nil {
		return errors.New("private subscription endpoint could not be verified after publication")
	}
	defer response.Body.Close()
	body, err := io.ReadAll(io.LimitReader(response.Body, 8192))
	if err != nil {
		return err
	}
	if response.StatusCode != http.StatusOK || string(body) != expected {
		return errors.New("private subscription endpoint did not return the exact locally generated body")
	}
	if !strings.Contains(strings.ToLower(response.Header.Get("Cache-Control")), "no-store") {
		return errors.New("private subscription endpoint is missing its no-store cache policy")
	}
	return nil
}
