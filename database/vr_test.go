package database

import (
	"os"
	"testing"
	"wwfc/common"
)

// Requires WWFC_TEST_DB=1 and a local database configured in config.xml.
func TestRatings(t *testing.T) {
	if os.Getenv("WWFC_TEST_DB") == "" {
		t.Skip("set WWFC_TEST_DB=1")
	}
	os.Chdir("..")
	c := Start(common.GetConfig())
	defer c.Close()
	c.createRatingTables()
	c.pool.Exec(c.ctx, `INSERT INTO users (profile_id,user_id,gsbrcd,password,email,unique_nick,last_ingamesn) VALUES (900001,1,'RMCPx','x','x','x','Franx'),(900002,2,'RMCPy','y','y','y','Luigi') ON CONFLICT DO NOTHING`)
	for _, v := range []int{5000, 5000, 5120, 5090} {
		if err := c.RecordRating(900001, "vr", v); err != nil {
			t.Fatal(err)
		}
	}
	c.RecordRating(900002, "vr", 7000)
	lb, err := c.GetLeaderboard("vr", 10, 0)
	if err != nil || len(lb) < 2 || lb[0].ProfileID != 900002 || lb[1].Rating != 5090 || lb[1].Name != "Franx" {
		t.Fatalf("leaderboard %+v %v", lb, err)
	}
	h, _ := c.GetRatingHistory(900001, "vr", 10)
	if len(h) != 3 {
		t.Fatalf("history should dedupe unchanged values, got %d", len(h))
	}
	c.pool.Exec(c.ctx, `DELETE FROM vr_history WHERE profile_id IN (900001,900002); DELETE FROM player_ratings WHERE profile_id IN (900001,900002); DELETE FROM users WHERE profile_id IN (900001,900002)`)
}
