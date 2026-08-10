package main

import (
	"sync"
	"testing"
)

func TestFacilityTokenBudgets_IsolatedPerFacility(t *testing.T) {
	budgets := NewFacilityTokenBudgets(1000)

	okA, _ := budgets.Reserve("facility-a", 900)
	if !okA {
		t.Fatal("facility-a の予約は成功するべき")
	}

	// facility-a がほぼ使い切っていても、facility-b には影響しない(独立したバケツ)。
	okB, _ := budgets.Reserve("facility-b", 900)
	if !okB {
		t.Fatal("facility-b は facility-a と独立した予算を持つべき")
	}
}

func TestFacilityTokenBudgets_EnforcesPerFacilityLimit(t *testing.T) {
	budgets := NewFacilityTokenBudgets(1000)

	ok1, _ := budgets.Reserve("facility-a", 600)
	if !ok1 {
		t.Fatal("1回目の予約は成功するべき")
	}

	ok2, remaining := budgets.Reserve("facility-a", 500)
	if ok2 {
		t.Fatal("上限を超える予約は拒否されるべき")
	}
	if remaining != 400 {
		t.Errorf("got remaining %d, want 400", remaining)
	}
}

func TestFacilityTokenBudgets_EmptyFacilityIDNormalized(t *testing.T) {
	budgets := NewFacilityTokenBudgets(1000)

	budgets.Reserve("", 100)
	if budgets.FacilityCount() != 1 {
		t.Fatalf("空文字列は unknown キーに正規化され1件として扱われるべき: got %d facilities", budgets.FacilityCount())
	}
}

// TestFacilityTokenBudgets_ConcurrentReserve は goroutine + sync.Mutex による
// 並行リクエストの安全性を検証する。同一施設に対して複数goroutineが同時に
// Reserve を呼んでも、合計予約数が上限を超えないことを確認する
// (go test -race でデータ競合がないことも確認できる)。
func TestFacilityTokenBudgets_ConcurrentReserve(t *testing.T) {
	const limit = 10_000
	const perRequest = 100
	const goroutines = 200 // 100トークン x 200 = 20,000 > 上限10,000 なので約半分は拒否されるはず

	budgets := NewFacilityTokenBudgets(limit)

	var wg sync.WaitGroup
	var mu sync.Mutex
	successCount := 0

	for i := 0; i < goroutines; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			ok, _ := budgets.Reserve("facility-concurrent", perRequest)
			if ok {
				mu.Lock()
				successCount++
				mu.Unlock()
			}
		}()
	}
	wg.Wait()

	totalReserved := successCount * perRequest
	if totalReserved > limit {
		t.Fatalf("並行アクセス時に上限を超えて予約された: %d > %d", totalReserved, limit)
	}
	if successCount != limit/perRequest {
		t.Errorf("got successCount %d, want %d (上限ちょうどまで予約できるはず)", successCount, limit/perRequest)
	}
}
