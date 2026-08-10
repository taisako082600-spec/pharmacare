package main

import "sync"

const unknownFacilityKey = "unknown"

// FacilityTokenBudgets は施設ごとのトークン予算を管理する。
// マップ自体へのアクセスは mu で保護するが、各施設の消費量管理は個々の *TokenBudget が担う。
// ロックの粒度を「マップの読み書き」と「個々の施設の増減」で分けているため、
// 異なる施設からの同時リクエストが互いをブロックしない
// (施設Aのリクエストが施設Bのリクエストの待ち時間を増やさない設計)。
type FacilityTokenBudgets struct {
	mu               sync.Mutex
	perFacility      map[string]*TokenBudget
	dailyLimitPerFac int
}

func NewFacilityTokenBudgets(dailyLimitPerFacility int) *FacilityTokenBudgets {
	return &FacilityTokenBudgets{
		perFacility:      make(map[string]*TokenBudget),
		dailyLimitPerFac: dailyLimitPerFacility,
	}
}

func normalizeFacilityID(facilityID string) string {
	if facilityID == "" {
		return unknownFacilityKey
	}
	return facilityID
}

func (f *FacilityTokenBudgets) budgetFor(facilityID string) *TokenBudget {
	key := normalizeFacilityID(facilityID)

	f.mu.Lock()
	defer f.mu.Unlock()

	b, ok := f.perFacility[key]
	if !ok {
		b = NewTokenBudget(f.dailyLimitPerFac)
		f.perFacility[key] = b
	}
	return b
}

// Reserve は指定施設の予算枠を確保する。施設ごとに独立した TokenBudget.Reserve を呼ぶ。
func (f *FacilityTokenBudgets) Reserve(facilityID string, estimatedTokens int) (ok bool, remaining int) {
	return f.budgetFor(facilityID).Reserve(estimatedTokens)
}

// Record は指定施設の実測トークン数で見積もりを補正する。
func (f *FacilityTokenBudgets) Record(facilityID string, estimated, actual int) {
	f.budgetFor(facilityID).Record(estimated, actual)
}

// Status は指定施設の消費状況を返す。
func (f *FacilityTokenBudgets) Status(facilityID string) string {
	return f.budgetFor(facilityID).Status()
}

// FacilityCount は現在追跡中の施設数を返す(監視・デバッグ用)。
func (f *FacilityTokenBudgets) FacilityCount() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.perFacility)
}
