// Kartaclysm: VR/BR history and leaderboard storage (AGPL-3.0, see LICENSE)
package database

import (
	"time"
)

type RatingEntry struct {
	Rank      int       `json:"rank"`
	ProfileID uint32    `json:"pid"`
	Name      string    `json:"name"`
	Rating    int       `json:"rating"`
	UpdatedAt time.Time `json:"updated"`
}

type RatingPoint struct {
	Rating int       `json:"rating"`
	Time   time.Time `json:"time"`
}

func (c *Connection) createRatingTables() {
	_, _ = c.pool.Exec(c.ctx, `
	CREATE TABLE IF NOT EXISTS public.vr_history (
		id bigserial PRIMARY KEY,
		profile_id bigint NOT NULL,
		kind character(2) NOT NULL,
		rating integer NOT NULL,
		recorded_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP
	);
	CREATE INDEX IF NOT EXISTS vr_history_pid ON public.vr_history (profile_id, kind, recorded_at);
	CREATE TABLE IF NOT EXISTS public.player_ratings (
		profile_id bigint NOT NULL,
		kind character(2) NOT NULL,
		rating integer NOT NULL,
		updated_at timestamp without time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
		PRIMARY KEY (profile_id, kind)
	);
	CREATE INDEX IF NOT EXISTS player_ratings_rank ON public.player_ratings (kind, rating DESC);
	`)
}

// RecordRating stores a rating if it changed. kind is "vr" or "br".
func (c *Connection) RecordRating(profileId uint32, kind string, rating int) error {
	tag, err := c.pool.Exec(c.ctx, `
	INSERT INTO public.player_ratings (profile_id, kind, rating, updated_at)
	VALUES ($1, $2, $3, CURRENT_TIMESTAMP)
	ON CONFLICT (profile_id, kind) DO UPDATE SET rating = EXCLUDED.rating, updated_at = CURRENT_TIMESTAMP
	WHERE public.player_ratings.rating <> EXCLUDED.rating`, profileId, kind, rating)
	if err != nil || tag.RowsAffected() == 0 {
		return err
	}
	_, err = c.pool.Exec(c.ctx, `INSERT INTO public.vr_history (profile_id, kind, rating) VALUES ($1, $2, $3)`, profileId, kind, rating)
	return err
}

func (c *Connection) GetLeaderboard(kind string, limit, offset int) ([]RatingEntry, error) {
	rows, err := c.pool.Query(c.ctx, `
	SELECT r.profile_id, COALESCE(u.last_ingamesn, ''), r.rating, r.updated_at
	FROM public.player_ratings r LEFT JOIN public.users u ON u.profile_id = r.profile_id
	WHERE r.kind = $1 AND COALESCE(u.has_ban, false) = false
	ORDER BY r.rating DESC, r.updated_at ASC LIMIT $2 OFFSET $3`, kind, limit, offset)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []RatingEntry{}
	for rows.Next() {
		var e RatingEntry
		var pid int64
		if err := rows.Scan(&pid, &e.Name, &e.Rating, &e.UpdatedAt); err != nil {
			return nil, err
		}
		e.ProfileID = uint32(pid)
		e.Rank = offset + len(out) + 1
		out = append(out, e)
	}
	return out, rows.Err()
}

func (c *Connection) GetRatingHistory(profileId uint32, kind string, limit int) ([]RatingPoint, error) {
	rows, err := c.pool.Query(c.ctx, `
	SELECT rating, recorded_at FROM public.vr_history WHERE profile_id = $1 AND kind = $2
	ORDER BY recorded_at DESC LIMIT $3`, profileId, kind, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []RatingPoint{}
	for rows.Next() {
		var p RatingPoint
		if err := rows.Scan(&p.Rating, &p.Time); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}
