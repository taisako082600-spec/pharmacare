package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
)

func main() {
	globalDailyLimit := 200_000 // デフォルト: 全体で1日20万トークン(安全弁)
	if v := os.Getenv("DAILY_TOKEN_LIMIT"); v != "" {
		if parsed, err := strconv.Atoi(v); err == nil {
			globalDailyLimit = parsed
		}
	}

	facilityDailyLimit := 50_000 // デフォルト: 施設ごとに1日5万トークン(公平性)
	if v := os.Getenv("DAILY_TOKEN_LIMIT_PER_FACILITY"); v != "" {
		if parsed, err := strconv.Atoi(v); err == nil {
			facilityDailyLimit = parsed
		}
	}

	firestoreClient, err := NewFirestoreClient()
	if err != nil {
		log.Fatalf("Firestoreクライアント初期化失敗: %v", err)
	}

	srv := &server{
		claude:          NewClaudeClient(),
		globalBudget:    NewTokenBudget(globalDailyLimit),
		facilityBudgets: NewFacilityTokenBudgets(facilityDailyLimit),
		firestore:       firestoreClient,
	}

	firebaseProjectID := os.Getenv("FIREBASE_PROJECT_ID")

	mux := http.NewServeMux()
	mux.HandleFunc("/v1/analyze-medication", requireAuth(firebaseProjectID, srv.analyzeMedicationHandler))
	mux.HandleFunc("/v1/triage", requireAuth(firebaseProjectID, srv.triageHandler))
	mux.HandleFunc("/v1/admin/fetch-drug-label", requireAuth(firebaseProjectID, srv.adminFetchDrugLabelHandler))
	mux.HandleFunc("/healthz", srv.healthHandler)
	// Cloud Run (*.run.app) のエッジ層は "/healthz" という文字列を予約パス扱いし、
	// コンテナに転送せずGoogle自前の404ページを返すことを実機検証で確認した(2026-07-20)。
	// /v1/triage 等の他パスは正常に転送される。原因はGoogle側の内部挙動のため
	// 特定不能だが、回避策として同じヘルスチェックを /ping にも登録しておく。
	// ローカル開発・他ホスティング先では引き続き /healthz も使える。
	mux.HandleFunc("/ping", srv.healthHandler)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8081"
	}

	if os.Getenv("ANTHROPIC_API_KEY") == "" {
		fmt.Println("警告: ANTHROPIC_API_KEY が未設定です。/v1/* エンドポイントはAI呼び出し時にエラーを返します。")
		fmt.Println("       (/healthz, /ping は正常に応答します)")
	}
	if firebaseProjectID == "" {
		fmt.Println("警告: FIREBASE_PROJECT_ID が未設定です。認証なしで起動します(開発用のみ)。")
	}
	if firestoreClient == nil {
		fmt.Println("警告: GOOGLE_APPLICATION_CREDENTIALS が未設定です。②医薬品注意点表示機能は無効化されます。")
	}

	fmt.Printf("PharmaCore LLMプロキシを起動しました: http://localhost:%s\n", port)
	fmt.Println("  POST /v1/analyze-medication")
	fmt.Println("  POST /v1/triage")
	fmt.Println("  POST /v1/admin/fetch-drug-label (管理者専用)")
	fmt.Println("  GET  /healthz (Cloud Run本番ではGoogle側エッジに横取りされるため /ping を推奨)")
	fmt.Println("  GET  /ping")

	log.Fatal(http.ListenAndServe(":"+port, mux))
}
