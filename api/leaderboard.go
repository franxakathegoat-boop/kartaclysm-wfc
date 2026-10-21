// Kartaclysm: public leaderboard API (AGPL-3.0, see LICENSE)
package api

import (
	"net/http"
	"strconv"
)

// GET /api/leaderboard?type=vr|br&limit=50&offset=0
func HandleLeaderboard(w http.ResponseWriter, r *http.Request) {
	query, err := parseGet(r, w, RoleNone)
	if err != nil {
		return
	}
	kind := query.Get("type")
	if kind == "" {
		kind = "vr"
	}
	if kind != "vr" && kind != "br" {
		replyError(w, http.StatusBadRequest, APIErrorInvalidQuery)
		return
	}
	limit := clampInt(query.Get("limit"), 50, 1, 500)
	offset := clampInt(query.Get("offset"), 0, 0, 1000000)
	list, err := db.GetLeaderboard(kind, limit, offset)
	if err != nil {
		replyError(w, http.StatusInternalServerError, APIErrorInvalidQuery)
		return
	}
	replyOK(w, map[string]any{"type": kind, "players": list})
}

// GET /api/vrhistory?pid=123&type=vr&limit=100
func HandleVRHistory(w http.ResponseWriter, r *http.Request) {
	query, err := parseGet(r, w, RoleNone)
	if err != nil {
		return
	}
	pid, err := strconv.ParseUint(query.Get("pid"), 10, 32)
	if err != nil || pid == 0 {
		replyError(w, http.StatusBadRequest, APIErrorInvalidProfileID)
		return
	}
	kind := query.Get("type")
	if kind != "br" {
		kind = "vr"
	}
	hist, err := db.GetRatingHistory(uint32(pid), kind, clampInt(query.Get("limit"), 100, 1, 1000))
	if err != nil {
		replyError(w, http.StatusInternalServerError, APIErrorInvalidQuery)
		return
	}
	replyOK(w, map[string]any{"pid": pid, "type": kind, "history": hist})
}

func clampInt(s string, def, lo, hi int) int {
	v, err := strconv.Atoi(s)
	if err != nil {
		return def
	}
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}
