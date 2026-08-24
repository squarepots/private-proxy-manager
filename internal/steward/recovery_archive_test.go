package steward

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

type fakeSevenZip struct {
	contents    string
	calls       [][]string
	failVerify  bool
	failExtract bool
}

func (fake *fakeSevenZip) run(_ string, args ...string) error {
	fake.calls = append(fake.calls, append([]string(nil), args...))
	switch args[0] {
	case "a":
		separator := argumentIndex(args, "--")
		archive, source := args[separator+1], args[separator+2]
		fake.contents = filepath.Join(filepath.Dir(archive), "fake-archive-contents")
		if err := os.RemoveAll(fake.contents); err != nil {
			return err
		}
		if err := copyTree(filepath.Dir(source), fake.contents); err != nil {
			return err
		}
		return os.WriteFile(archive, []byte("fake encrypted archive"), 0o600)
	case "t":
		if fake.failVerify {
			return errors.New("synthetic verification failure")
		}
		return nil
	case "x":
		if fake.failExtract {
			return errors.New("synthetic extraction failure")
		}
		var destination string
		for _, argument := range args {
			if strings.HasPrefix(argument, "-o") {
				destination = strings.TrimPrefix(argument, "-o")
			}
		}
		return copyTree(fake.contents, destination)
	default:
		return errors.New("unexpected fake 7-Zip operation")
	}
}

func TestRecoveryArchiveRoundTripUsesLocalSevenZipPrompt(t *testing.T) {
	root := t.TempDir()
	privateDir := filepath.Join(root, "private")
	state, _, err := Bootstrap(privateDir)
	if err != nil {
		t.Fatal(err)
	}
	key := filepath.Join(privateDir, "fixture.pem")
	if err := os.WriteFile(key, []byte("synthetic-key"), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := AddServer(state, map[string]any{
		"server_id": "entry-a", "public_ipv4": "192.0.2.50", "ssh_user": "ubuntu",
		"ssh_key_path": key, "host_ownership": "dedicated",
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := AddRoute(state, map[string]any{"route_id": "direct-a", "display_name": "Direct-A", "kind": "direct", "entry_server": "entry-a", "listen_port": 443}); err != nil {
		t.Fatal(err)
	}
	route := findRoute(state.Inventory, "direct-a")
	route.Enabled, route.State = true, "deployed"
	if err := state.Save(false); err != nil {
		t.Fatal(err)
	}
	now := func() time.Time { return time.Date(2026, 8, 24, 12, 0, 0, 0, time.UTC) }
	txn, err := newMigrationTransaction(state, "direct-a", map[string]any{
		"replacement_server_id": "replacement-b",
		"replacement_server":    map[string]any{"public_ipv4": "198.51.100.60", "ssh_user": "ubuntu", "ssh_key_path": key, "host_ownership": "dedicated"},
	}, now)
	if err != nil {
		t.Fatal(err)
	}
	migrations := &migrationState{Schema: 1, Transactions: []migrationTransaction{txn}}
	if err := saveMigrationState(state.PrivateDir, migrations, &migrations.Transactions[0], now); err != nil {
		t.Fatal(err)
	}
	fakeExecutable := filepath.Join(root, "7z-fixture")
	if err := os.WriteFile(fakeExecutable, []byte("fixture"), 0o700); err != nil {
		t.Fatal(err)
	}

	fake := &fakeSevenZip{}
	originalRunner := runInteractive
	runInteractive = fake.run
	t.Cleanup(func() { runInteractive = originalRunner })

	archive, err := CreateRecoveryArchive(state, fakeExecutable)
	if err != nil {
		t.Fatal(err)
	}
	if len(fake.calls) != 2 || fake.calls[0][0] != "a" || fake.calls[1][0] != "t" {
		t.Fatalf("unexpected 7-Zip calls: %#v", fake.calls)
	}
	for _, call := range fake.calls {
		if !contains(call, "-p") {
			t.Fatalf("7-Zip did not receive the bare local-prompt option: %#v", call)
		}
		for _, argument := range call {
			if strings.HasPrefix(argument, "-p") && argument != "-p" {
				t.Fatalf("a password entered a process argument: %q", argument)
			}
		}
	}
	if !contains(fake.calls[0], "-mhe=on") {
		t.Fatal("recovery archive did not request encrypted headers")
	}

	destination := filepath.Join(root, "restored")
	result, err := RestoreRecoveryArchive(archive, destination, fakeExecutable)
	if err != nil {
		t.Fatal(err)
	}
	if len(fake.calls) != 3 || fake.calls[2][0] != "x" || !contains(fake.calls[2], "-p") || !contains(fake.calls[2], "--") {
		t.Fatalf("restore did not use the expected local-prompt extraction call: %#v", fake.calls)
	}
	for _, argument := range fake.calls[2] {
		if strings.HasPrefix(argument, "-p") && argument != "-p" {
			t.Fatalf("a restore password entered a process argument: %q", argument)
		}
	}
	if restored, _ := result["restored"].(bool); !restored {
		t.Fatalf("recovery result is incomplete: %#v", result)
	}
	if migrationRestored, _ := result["migration_state_restored"].(bool); !migrationRestored {
		t.Fatalf("active migration checkpoint was not restored: %#v", result)
	}
	restored, err := LoadState(destination)
	if err != nil {
		t.Fatal(err)
	}
	if len(restored.Inventory.Servers) != 1 || !regularFile(restored.Inventory.Servers[0].SSH.KeyPath) {
		t.Fatal("round-trip recovery did not restore the server SSH key")
	}
	restoredMigrations, err := readMigrationState(destination)
	if err != nil || len(restoredMigrations.Transactions) != 1 {
		t.Fatalf("migration checkpoint recovery failed: %#v err=%v", restoredMigrations, err)
	}
	restoredTxn := restoredMigrations.Transactions[0]
	if restoredTxn.Phase != "planned" || restoredTxn.LastFailure != "recovery-revalidation-required" || !regularFile(stringField(restoredTxn.ReplacementServerContext, "ssh_key_path")) {
		t.Fatalf("restored migration is not safely resumable: %#v", restoredTxn)
	}
}

func TestRecoveryArchiveFailuresLeaveNoOutput(t *testing.T) {
	root := t.TempDir()
	state, _, err := Bootstrap(filepath.Join(root, "private"))
	if err != nil {
		t.Fatal(err)
	}
	fakeExecutable := filepath.Join(root, "7z-fixture")
	if err := os.WriteFile(fakeExecutable, []byte("fixture"), 0o700); err != nil {
		t.Fatal(err)
	}
	fake := &fakeSevenZip{failVerify: true}
	originalRunner := runInteractive
	runInteractive = fake.run
	t.Cleanup(func() { runInteractive = originalRunner })

	if _, err := CreateRecoveryArchive(state, fakeExecutable); err == nil {
		t.Fatal("failed archive verification was accepted")
	}
	archive := fake.calls[0][argumentIndex(fake.calls[0], "--")+1]
	if _, err := os.Stat(archive); !os.IsNotExist(err) {
		t.Fatal("failed archive verification left a recovery archive")
	}

	fake.failVerify = false
	fake.failExtract = false
	archive, err = CreateRecoveryArchive(state, fakeExecutable)
	if err != nil {
		t.Fatal(err)
	}
	fake.failExtract = true
	destination := filepath.Join(root, "failed-restore")
	if _, err := RestoreRecoveryArchive(archive, destination, fakeExecutable); err == nil {
		t.Fatal("failed archive extraction was accepted")
	}
	if _, err := os.Stat(destination); !os.IsNotExist(err) {
		t.Fatal("failed archive extraction left a recovery destination")
	}
}

func argumentIndex(arguments []string, value string) int {
	for index, argument := range arguments {
		if argument == value {
			return index
		}
	}
	return -1
}
