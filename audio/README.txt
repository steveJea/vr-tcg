메인 화면 배경음악: 이 폴더에 main.mp3 를 넣으면 자동 재생(반복)됩니다.

# 추가 BGM (feat/bgm-more, 128kbps 재인코딩)
arcade_battle.mp3  아케이드 전투 (나가면 main.mp3) — 10/29 ARCADE_MODE 로 교체
tower.mp3          시련의 탑 화면·일반 층 (10층마다 보스층은 story_boss.mp3)
gacha.mp3          카드 뽑기실
mypage.mp3         마이페이지·카드 도감 (닫으면 이전 트랙)
victory.mp3 / defeat.mp3  전투 종료 징글 1회 (VRSound.jingle) — 반복 BGM 페이드아웃 후 정지, 징글 끝나면 현재 트랙 페이드인
draw.mp3           무승부 징글 1회 (VRSound.jingle('draw')) — 10/29 DRAW_GAME 로 교체
gacha_sr.mp3 / gacha_ur.mp3  뽑기 등급 연출 스팅어 (SR / UR·MR). 10/29 GOT_SR / GOT_UR 로 교체. 효과음 취급: 효과음 토글, 음량 0.25×보이스 음량, 재생 중 BGM 덕킹
story_boss2.mp3    스토리 보스전 BGM 2 (BOSS_2, 챕터 8부터 보스 페이즈·ph.bgm='boss'. 그 전 챕터는 story_boss.mp3)

# 모드별 BGM (10/29, 128kbps). 화면 BGM = VRSound.scope(화면, 트랙): 화면 닫히면 들어오기 전 트랙 · 전투 BGM = viewBattle({ music }): 끝나면 화면 트랙
pvp_lobby.mp3      PvP 대기실 (PVP_LOBBY)
pvp_battle.mp3     PvP 전투 (PVP_BATTLE)
raid.mp3           균열 토벌 화면·전투 (RAID)
guild_lobby.mp3    조직(길드) 홈 (GUILD_LOBBY). 구역 전쟁 화면도 이어서 재생
guild_battle.mp3   구역 전쟁 전투 (GUILD_BATTLE)
