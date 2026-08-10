package main

import (
	"fmt"
	"sync"
	"time"
)

// TokenBudget は日次のトークン消費量を追跡し、上限を超えるリクエストを拒否する。
// 複数の施設・薬剤師が同時にリクエストしても安全なよう sync.Mutex で排他制御する
// (go-crud-sample の store と同じ Lock -> defer Unlock パターン)。
type TokenBudget struct {
	mu          sync.Mutex
	dailyLimit  int
	usedToday   int
	windowStart time.Time
}

func NewTokenBudget(dailyLimit int) *TokenBudget {
	return &TokenBudget{
		dailyLimit:  dailyLimit,
		windowStart: time.Now(),
	}
}

func (b *TokenBudget) resetIfNewDayLocked() {
	if time.Since(b.windowStart) >= 24*time.Hour {
		b.usedToday = 0
		b.windowStart = time.Now()
	}
}

// Reserve は見積もりトークン数(count_tokensの結果、または概算値)が上限内に収まるか確認し、
// 収まればその場で消費量に加算する(先に枠を確保してからAPIを呼ぶことで、
// 並行リクエストが同時に上限を超えて通過するのを防ぐ)。
// 上限超過時は ok=false を返し、呼び出し元はAPIを呼ばずに 429 を返す。
func (b *TokenBudget) Reserve(estimatedTokens int) (ok bool, remaining int) {
	b.mu.Lock()
	defer b.mu.Unlock()

	b.resetIfNewDayLocked()

	if b.usedToday+estimatedTokens > b.dailyLimit {
		return false, b.dailyLimit - b.usedToday
	}

	b.usedToday += estimatedTokens
	return true, b.dailyLimit - b.usedToday
}

// Record は実際にAPIが消費したトークン数(レスポンスの usage 実測値)で
// 見積もりとの差分を補正する。見積もりが実際より少なかった場合は追加で加算され、
// 多かった場合は差し戻される。
func (b *TokenBudget) Record(estimated, actual int) {
	b.mu.Lock()
	defer b.mu.Unlock()

	diff := actual - estimated
	b.usedToday += diff
	if b.usedToday < 0 {
		b.usedToday = 0
	}
}

func (b *TokenBudget) Status() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.resetIfNewDayLocked()
	return fmt.Sprintf("%d/%d tokens used today", b.usedToday, b.dailyLimit)
}
