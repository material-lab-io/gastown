package cmd

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/steveyegge/gastown/internal/mail"
)

// TestLoadMailCheckSnapshotCacheHit verifies that inject mode returns cached
// messages without calling List() when a valid cache entry exists.
func TestLoadMailCheckSnapshotCacheHit(t *testing.T) {
	tmp := t.TempDir()
	os.Setenv("XDG_CACHE_HOME", tmp)
	defer os.Unsetenv("XDG_CACHE_HOME")

	mailCheckInject = true
	mailCheckNoCache = false
	defer func() {
		mailCheckInject = false
		mailCheckNoCache = false
	}()

	address := "gastown/polecats/toast"
	cachedMsgs := []*mail.Message{
		{ID: "msg-cached-1", Read: false},
		{ID: "msg-cached-2", Read: true},
	}
	data, _ := json.MarshalIndent(cachedMsgs, "", "  ")
	data = append(data, '\n')
	writeInboxCache(inboxCacheKey(address, false), data)

	box := &fakeInboxLister{
		messages: []*mail.Message{{ID: "msg-live"}},
	}

	msgs, total, unread, err := loadMailCheckSnapshot(box, address)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if box.calls != 0 {
		t.Fatalf("List called %d time(s) on cache hit, want 0", box.calls)
	}
	if total != 2 || unread != 1 {
		t.Fatalf("counts = (%d, %d), want (2, 1)", total, unread)
	}
	if len(msgs) != 2 || msgs[0].ID != "msg-cached-1" {
		t.Fatalf("got msgs[0].ID=%q, want msg-cached-1", msgs[0].ID)
	}
}

// TestLoadMailCheckSnapshotCacheMissPopulatesCache verifies that inject mode
// falls through to List() on a cache miss and writes the result to cache.
func TestLoadMailCheckSnapshotCacheMissPopulatesCache(t *testing.T) {
	tmp := t.TempDir()
	os.Setenv("XDG_CACHE_HOME", tmp)
	defer os.Unsetenv("XDG_CACHE_HOME")

	mailCheckInject = true
	mailCheckNoCache = false
	defer func() {
		mailCheckInject = false
		mailCheckNoCache = false
	}()

	address := "gastown/polecats/nux"
	box := &fakeInboxLister{
		messages: []*mail.Message{
			{ID: "msg-live-1", Read: false},
			{ID: "msg-live-2", Read: false},
		},
	}

	msgs, total, unread, err := loadMailCheckSnapshot(box, address)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if box.calls != 1 {
		t.Fatalf("List calls = %d, want 1 on cache miss", box.calls)
	}
	if total != 2 || unread != 2 {
		t.Fatalf("counts = (%d, %d), want (2, 2)", total, unread)
	}
	if len(msgs) != 2 {
		t.Fatalf("msgs len = %d, want 2", len(msgs))
	}

	// Second call should hit the cache — no additional List() calls
	msgs2, _, _, err := loadMailCheckSnapshot(box, address)
	if err != nil {
		t.Fatalf("second call unexpected error: %v", err)
	}
	if box.calls != 1 {
		t.Fatalf("List calls after cache populate = %d, want still 1", box.calls)
	}
	if len(msgs2) != 2 || msgs2[0].ID != "msg-live-1" {
		t.Fatalf("second call got wrong messages")
	}
}

// TestLoadMailCheckSnapshotNoCacheBypass verifies --no-cache always calls List().
func TestLoadMailCheckSnapshotNoCacheBypass(t *testing.T) {
	tmp := t.TempDir()
	os.Setenv("XDG_CACHE_HOME", tmp)
	defer os.Unsetenv("XDG_CACHE_HOME")

	mailCheckInject = true
	mailCheckNoCache = true
	defer func() {
		mailCheckInject = false
		mailCheckNoCache = false
	}()

	address := "gastown/polecats/wolf"
	// Seed cache with stale data
	writeInboxCache(inboxCacheKey(address, false), []byte(`[{"id":"stale"}]`))

	box := &fakeInboxLister{
		messages: []*mail.Message{{ID: "msg-fresh"}},
	}

	msgs, _, _, err := loadMailCheckSnapshot(box, address)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if box.calls != 1 {
		t.Fatalf("List calls = %d, want 1 when --no-cache", box.calls)
	}
	if msgs[0].ID != "msg-fresh" {
		t.Fatalf("got msg ID %q, want msg-fresh", msgs[0].ID)
	}
}

// TestLoadMailCheckSnapshotNonInjectSkipsCache verifies that non-inject mode
// always queries live.
func TestLoadMailCheckSnapshotNonInjectSkipsCache(t *testing.T) {
	tmp := t.TempDir()
	os.Setenv("XDG_CACHE_HOME", tmp)
	defer os.Unsetenv("XDG_CACHE_HOME")

	mailCheckInject = false
	mailCheckNoCache = false
	defer func() { mailCheckInject = false }()

	address := "gastown/polecats/furiosa"
	writeInboxCache(inboxCacheKey(address, false), []byte(`[{"id":"cached"}]`))

	box := &fakeInboxLister{
		messages: []*mail.Message{{ID: "msg-live"}},
	}

	msgs, _, _, err := loadMailCheckSnapshot(box, address)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if box.calls != 1 {
		t.Fatalf("List calls = %d, want 1 when not inject mode", box.calls)
	}
	if msgs[0].ID != "msg-live" {
		t.Fatalf("got msg ID %q, want msg-live", msgs[0].ID)
	}
}

// TestInvalidateInboxCacheRemovesBothKeys verifies that invalidateInboxCache
// removes both the all-messages and unread-only cache entries.
func TestInvalidateInboxCacheRemovesBothKeys(t *testing.T) {
	tmp := t.TempDir()
	os.Setenv("XDG_CACHE_HOME", tmp)
	defer os.Unsetenv("XDG_CACHE_HOME")

	address := "gastown/polecats/toast"
	key1 := inboxCacheKey(address, false)
	key2 := inboxCacheKey(address, true)

	writeInboxCache(key1, []byte(`[]`))
	writeInboxCache(key2, []byte(`[]`))

	if _, ok := readInboxCache(key1); !ok {
		t.Fatal("expected cache hit for all-messages key before invalidate")
	}
	if _, ok := readInboxCache(key2); !ok {
		t.Fatal("expected cache hit for unread-only key before invalidate")
	}

	invalidateInboxCache(address)

	if _, ok := readInboxCache(key1); ok {
		t.Fatal("expected cache miss for all-messages key after invalidate")
	}
	if _, ok := readInboxCache(key2); ok {
		t.Fatal("expected cache miss for unread-only key after invalidate")
	}
}

// TestLoadMailCheckSnapshotCacheExpiry verifies that expired cache entries
// trigger a live Dolt query.
func TestLoadMailCheckSnapshotCacheExpiry(t *testing.T) {
	tmp := t.TempDir()
	os.Setenv("XDG_CACHE_HOME", tmp)
	defer os.Unsetenv("XDG_CACHE_HOME")

	mailCheckInject = true
	mailCheckNoCache = false
	inboxCacheTTLOverride = 1 * time.Millisecond
	defer func() {
		mailCheckInject = false
		mailCheckNoCache = false
		inboxCacheTTLOverride = 0
	}()

	address := "gastown/polecats/speedy"
	key := inboxCacheKey(address, false)
	writeInboxCache(key, []byte(`[{"id":"old"}]`))

	// Backdate the cache file so it looks expired
	p := filepath.Join(tmp, "gastown", "mail-inbox", key+".json")
	past := time.Now().Add(-1 * time.Second)
	_ = os.Chtimes(p, past, past)

	box := &fakeInboxLister{
		messages: []*mail.Message{{ID: "msg-fresh"}},
	}

	msgs, _, _, err := loadMailCheckSnapshot(box, address)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if box.calls != 1 {
		t.Fatalf("List calls = %d, want 1 on expired cache", box.calls)
	}
	if msgs[0].ID != "msg-fresh" {
		t.Fatalf("got msg ID %q, want msg-fresh", msgs[0].ID)
	}
}
