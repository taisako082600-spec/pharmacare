package main

import (
	"context"
	"net/http"
	"strings"
)

type contextKey string

const uidContextKey contextKey = "firebaseUID"

// requireAuth はAuthorizationヘッダーのFirebase IDトークンを検証するミドルウェア。
// projectID が空の場合は開発用として認証をスキップする(起動時に警告を出す)。
// 本番相当で使う場合は必ず FIREBASE_PROJECT_ID を設定すること。
func requireAuth(projectID string, next http.HandlerFunc) http.HandlerFunc {
	if projectID == "" {
		return next
	}

	return func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		if !strings.HasPrefix(authHeader, "Bearer ") {
			writeError(w, http.StatusUnauthorized, "Authorization: Bearer <Firebase ID Token> ヘッダーが必要です")
			return
		}
		idToken := strings.TrimPrefix(authHeader, "Bearer ")

		claims, err := VerifyFirebaseIDToken(idToken, projectID)
		if err != nil {
			writeError(w, http.StatusUnauthorized, "認証に失敗しました: "+err.Error())
			return
		}

		ctx := context.WithValue(r.Context(), uidContextKey, claims.UID)
		next(w, r.WithContext(ctx))
	}
}
