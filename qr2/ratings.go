// Kartaclysm: record VR/BR reported in QR2 heartbeats (AGPL-3.0, see LICENSE)
package qr2

import (
	"strconv"
	"sync"
	"wwfc/common"
	"wwfc/database"
	"wwfc/logging"
)

var (
	ratingDB      *database.Connection
	ratingMutex   sync.Mutex
	lastRatings   = map[string]int{}
	ratingQueue   = make(chan ratingUpdate, 1024)
	ratingStarted sync.Once
)

type ratingUpdate struct {
	pid    uint32
	kind   string
	rating int
}

func startRatingRecorder(config common.Config) {
	ratingStarted.Do(func() {
		db := database.Start(config)
		ratingDB = &db
		go func() {
			for u := range ratingQueue {
				if err := ratingDB.RecordRating(u.pid, u.kind, u.rating); err != nil {
					logging.Error("QR2", "Failed to record rating:", err.Error())
				}
			}
		}()
	})
}

// recordRating is called with a validated heartbeat payload of a logged-in session.
func recordRating(profileId uint32, payload map[string]string) {
	if ratingDB == nil || profileId == 0 || payload["gamename"] != "mariokartwii" {
		return
	}
	public, isBattle := isPublicMatchRegion(payload["rk"])
	if !public {
		return
	}
	kind, key := "vr", "ev"
	if isBattle {
		kind, key = "br", "eb"
	}
	v, err := strconv.Atoi(payload[key])
	if err != nil || v < 1 || v > 9999 {
		return
	}
	k := strconv.FormatUint(uint64(profileId), 10) + kind
	ratingMutex.Lock()
	if lastRatings[k] == v {
		ratingMutex.Unlock()
		return
	}
	lastRatings[k] = v
	ratingMutex.Unlock()
	select {
	case ratingQueue <- ratingUpdate{profileId, kind, v}:
	default:
	}
}
