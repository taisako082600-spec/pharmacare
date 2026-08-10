package main

import "testing"

func TestDetermineTriageResult(t *testing.T) {
	cases := []struct {
		name              string
		symptomCategory   string
		redFlags          map[string]bool
		consultationFlags map[string]bool
		severityScore     int
		wantResult        string
		wantOverride      bool
	}{
		{
			name:            "レッドフラッグありは重症度に関わらず受診推奨",
			symptomCategory: "cold",
			redFlags:        map[string]bool{"highFever38Plus": true},
			severityScore:   1,
			wantResult:      "medical_referral",
			wantOverride:    true,
		},
		{
			name:            "レッドフラッグなし・軽症はOTC対応可",
			symptomCategory: "cold",
			redFlags:        map[string]bool{"highFever38Plus": false},
			severityScore:   2,
			wantResult:      "otc_suitable",
			wantOverride:    false,
		},
		{
			name:            "レッドフラッグなし・重症度4以上は要相談",
			symptomCategory: "cold",
			redFlags:        map[string]bool{},
			severityScore:   4,
			wantResult:      "consultation",
			wantOverride:    false,
		},
		{
			name:            "レッドフラッグは重症度5でも受診推奨を優先する",
			symptomCategory: "pain",
			redFlags:        map[string]bool{"severePain": true},
			severityScore:   5,
			wantResult:      "medical_referral",
			wantOverride:    true,
		},
		{
			name:            "レッドフラッグが複数あっても受診推奨のまま",
			symptomCategory: "pain",
			redFlags:        map[string]bool{"severePain": true, "painWithVomiting": true},
			severityScore:   1,
			wantResult:      "medical_referral",
			wantOverride:    true,
		},
		{
			name:            "意識障害カテゴリはレッドフラッグ未チェック・軽症でも受診推奨",
			symptomCategory: "consciousness",
			redFlags:        map[string]bool{},
			severityScore:   1,
			wantResult:      "medical_referral",
			wantOverride:    true,
		},
		{
			name:              "consultationFlagsのみ該当は受診推奨(赤)ではなく要相談(黄)に留める",
			symptomCategory:   "cold",
			redFlags:          map[string]bool{},
			consultationFlags: map[string]bool{"oneSymptomDominant": true},
			severityScore:     1,
			wantResult:        "consultation",
			wantOverride:      false,
		},
		{
			name:              "redFlagsとconsultationFlagsが両方ある場合はredFlagsが優先",
			symptomCategory:   "cold",
			redFlags:          map[string]bool{"highFever38Plus": true},
			consultationFlags: map[string]bool{"oneSymptomDominant": true},
			severityScore:     1,
			wantResult:        "medical_referral",
			wantOverride:      true,
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			result, override := DetermineTriageResult(c.symptomCategory, c.redFlags, c.consultationFlags, c.severityScore)
			if result != c.wantResult {
				t.Errorf("got result %q, want %q", result, c.wantResult)
			}
			if override != c.wantOverride {
				t.Errorf("got redFlagOverride %v, want %v", override, c.wantOverride)
			}
		})
	}
}

func TestApplyVitalsRedFlags(t *testing.T) {
	f := func(v float64) *float64 { return &v }

	cases := []struct {
		name            string
		symptomCategory string
		spo2            *float64
		bpSystolic      *float64
		wantKey         string
		wantPresent     bool
	}{
		{
			name:            "SpO2が90未満なら自動でレッドフラッグ",
			symptomCategory: "coughDyspnea",
			spo2:            f(88),
			wantKey:         "vitalsLowSpO2",
			wantPresent:     true,
		},
		{
			name:            "SpO2が90以上なら発火しない",
			symptomCategory: "coughDyspnea",
			spo2:            f(95),
			wantKey:         "vitalsLowSpO2",
			wantPresent:     false,
		},
		{
			name:            "頭痛+収縮期血圧180以上は自動でレッドフラッグ",
			symptomCategory: "headache",
			bpSystolic:      f(185),
			wantKey:         "vitalsSevereHypertension",
			wantPresent:     true,
		},
		{
			name:            "頭痛以外のカテゴリでは血圧のみで発火しない",
			symptomCategory: "fever",
			bpSystolic:      f(185),
			wantKey:         "vitalsSevereHypertension",
			wantPresent:     false,
		},
		{
			name:            "測定値なしなら何も発火しない",
			symptomCategory: "headache",
			wantKey:         "vitalsSevereHypertension",
			wantPresent:     false,
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			result := ApplyVitalsRedFlags(c.symptomCategory, map[string]bool{}, c.spo2, c.bpSystolic)
			if result[c.wantKey] != c.wantPresent {
				t.Errorf("got %s=%v, want %v", c.wantKey, result[c.wantKey], c.wantPresent)
			}
		})
	}
}
