#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <zombiereloaded>
#include <csgocolors_fix>

#undef REQUIRE_EXTENSIONS
#include <outputinfo>
#define REQUIRE_EXTENSIONS

#pragma newdecls required
#define PLUGIN_VERSION "1.3"

public Plugin myinfo = {
	name = "Boss_Hud",
	author = "Anubis, Strellic",
	description = "Plugin that displays boss and breakable health.",
	url = "https://github.com/Stewart-Anubis",
	version = PLUGIN_VERSION
};

Handle HitTimer[MAXPLAYERS+1];

//bool starttimer = false;
char Clinet_message[MAXPLAYERS+1][512];
// colors
#define COLOR_SIMPLEHUD	 "#FF0000"
#define COLOR_BOSSNAME	  "#FF00FF"
#define COLOR_TOPBOSSDMG	"#FF0000"
#define COLOR_CIRCLEHI	  "#FFFF00"
#define COLOR_CIRCLEMID	 "#FFFF00"
#define COLOR_CIRCLELOW	 "#FFFF00"

// delays
#define DELAY_SIMPLEHUD	 2
#define DELAY_BOSSDEAD	  3
#define DELAY_BOSSTIMEOUT   10
#define DELAY_MULTBOSS	  1
#define DELAY_HITMARKER	 2
#define DELAY_HUDUPDATE	 0.75

#define BOSS_NAME_LEN 256
#define MAX_BOSSES 64

// any breakables above this HP won't be triggered
#define MAX_BREAKABLE_HP 900000

enum HPType {
	decreasing,
	increasing,
	none
};

enum struct Boss {
	char szDisplayName[BOSS_NAME_LEN];
	char szTargetName[BOSS_NAME_LEN];
	char szHPBarName[BOSS_NAME_LEN];
	char szHPInitName[BOSS_NAME_LEN];

	int iBossEnt;
	int iHPCounterEnt;
	int iInitEnt;

	int iMaxBars;
	int iCurrentBars;

	int iHP;
	int iInitHP;
	int iHighestHP;
	int iHighestTotalHP;

	int iForceBars;

	HPType hpBarMode;
	HPType hpMode;

	int iDamage[MAXPLAYERS+1];
	int iTotalHits;

	bool bDead;
	bool bDeadInit;
	bool bActive;

	int iLastHit;
	int iFirstActive;
}

enum struct SimpleHUD {
	int iEntID[MAXPLAYERS+1];
	int iTimer[MAXPLAYERS+1];
}

enum struct BossHud_Enum
{
	bool e_bHpBhEnable;
	bool e_bHpBrEnable;
	bool e_bHitmEnable;
	bool e_bHitmSound;
	bool e_bIsHitEnabled;
}

bool g_bBossHud,
	g_bBreakableHud,
	g_bDamgeHud,
	g_bShowTopDMG,
	g_bMultBoss,
	g_bMultHP,
	g_bIsFired[MAXPLAYERS+1],
	g_bBoshudDebugger[MAXPLAYERS+1];

int g_iBosses,
	g_iMultShowing,
	g_iMultLastSwitch,
	g_bOutputInfo,
	g_iHitmarkerTime[MAXPLAYERS + 1] = {-1, ...},
	g_iOutValueOffset = -1,
	g_iTotalSGDamage[MAXPLAYERS+1],
	g_iColor[MAXPLAYERS + 1][3];

Handle g_hHpBhEnable = INVALID_HANDLE,
	g_hHpBrEnable = INVALID_HANDLE,
	g_hHitmEnable = INVALID_HANDLE,
	g_hHitmSound = INVALID_HANDLE,
	g_hIsHitEnabled = INVALID_HANDLE,
	g_hTimer = INVALID_HANDLE;

ConVar g_cBossHud = null,
	g_cBreakableHud =null,
	g_cDamgeHud =null,
	g_cVUpdateTime = null,
	g_cVBossHitmarker = null,
	g_cVZombieHitmarker = null,
	g_cCvarSound = null;

char g_sBossHitmarker[PLATFORM_MAX_PATH],
	g_sZombieHitmarker[PLATFORM_MAX_PATH],
	g_sCvarSound[PLATFORM_MAX_PATH];

float g_fVUpdateTime;

bool didhit[MAXPLAYERS+1];
bool showhud[MAXPLAYERS+1];

BossHud_Enum BossHudClientEnum[MAXPLAYERS+1];
Boss bosses[MAX_BOSSES];
SimpleHUD simplehud;
StringMap EntityMaxes;

public void OnPluginStart()
{
	LoadTranslations("boss_hud.phrases");
	LoadTranslations("common.phrases");
	LoadTranslations("core.phrases");

	g_hHpBhEnable = RegClientCookie("Boss_Hud_Enable", "Boss Hud Enable", CookieAccess_Protected);
	g_hHpBrEnable = RegClientCookie("Boss_Breakable", "Boss Breakable", CookieAccess_Protected);
	g_hHitmEnable = RegClientCookie("Boss_Hit_Marker", "Boss Hit Marker", CookieAccess_Protected);
	g_hHitmSound = RegClientCookie("Boss_Hit_Marker_Sound", "Boss Hit Marker Sound", CookieAccess_Protected);
	g_hIsHitEnabled = RegClientCookie("Boss_Hits_Zomvbies", "Boss Hit Zombies", CookieAccess_Protected);


	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	//HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_PostNoCopy);

	LoadConfig();

	for(int client = 1; client <= MaxClients; client++)
	{ 
		if (IsClientInGame(client) && AreClientCookiesCached(client))
		{	
			OnClientCookiesCached(client);
		}
	}

	RegConsoleCmd("sm_bosshud",		 Command_ToggleBHUD, "Toggles BHUD & Hitmarkers");
	RegConsoleCmd("sm_bosshmarker",	 Command_ToggleBHUD, "Toggles BHUD & Hitmarkers");
	RegConsoleCmd("sm_bosshitm",		Command_ToggleBHUD, "Toggles BHUD & Hitmarkers");
	RegConsoleCmd("sm_bosshm",		  Command_ToggleBHUD, "Toggles BHUD & Hitmarkers");
	RegConsoleCmd("sm_bosshitmarker",   Command_ToggleBHUD, "Toggles BHUD & Hitmarkers");
	RegConsoleCmd("sm_bhitmarker",	  Command_ToggleBHUD, "Toggles BHUD & Hitmarkers");
	RegConsoleCmd("sm_bhm",			 Command_ToggleBHUD, "Toggles BHUD & Hitmarkers");
	RegConsoleCmd("sm_bhud",			Command_ToggleBHUD, "Toggles BHUD & Hitmarkers");

	RegAdminCmd("sm_currenthp",	 Command_CHP, ADMFLAG_GENERIC, "See Current HP");
	RegAdminCmd("sm_subtracthp",	Command_SHP, ADMFLAG_GENERIC, "Subtract Current HP");
	RegAdminCmd("sm_addhp",		 Command_AHP, ADMFLAG_GENERIC, "Add Current HP");
	RegAdminCmd("sm_bhuddebug", Command_BhudDebug, ADMFLAG_GENERIC, "Bhud_Debug");

	HookEntityOutput("func_physbox",				"OnHealthChanged",  Output_OnHealthChanged);
	HookEntityOutput("func_physbox_multiplayer",	"OnHealthChanged",  Output_OnHealthChanged);
	HookEntityOutput("func_breakable",			  "OnHealthChanged",  Output_OnHealthChanged);
	HookEntityOutput("func_physbox",				"OnBreak",		  Output_OnBreak);
	HookEntityOutput("func_physbox_multiplayer",	"OnBreak",		  Output_OnBreak);
	HookEntityOutput("func_breakable",			  "OnBreak",		  Output_OnBreak);
	HookEntityOutput("math_counter",				"OutValue",		 Output_OutValue);

	EntityMaxes = CreateTrie();
	ClearTrie(EntityMaxes);

	g_cBossHud = CreateConVar("sm_boss_hud", "1", "Boss Hud Enable = 1/Disable = 0");
	g_cBreakableHud = CreateConVar("sm_boss_breakable_hud", "1", "Breakable Hud Enable = 1/Disable = 0");
	g_cDamgeHud = CreateConVar("sm_boss_damge_hud", "1", "Damge Hud Enable = 1/Disable = 0");
	g_cVUpdateTime = CreateConVar("sm_boss_hud_updatetime", "1.02", "Delay between each update of the BHUD hud.", _, true, 0.0);
	g_cVBossHitmarker = CreateConVar("sm_boss_hud_hitmarker_vmt", "overlays/AA/hitmarker_tiiko_boss.vmt", "Path to boss hitmarker's vmt. materials/");
	g_cVZombieHitmarker = CreateConVar("sm_boss_hud_zombie_hitmarker_vmt", "overlays/AA/hitmarker_tiiko_zombie.vmt", "Path to zombie hitmarker's vmt. materials/");
	g_cCvarSound = CreateConVar("sm_boss_hud_hitmarker_sound", "iex/hit.mp3", "Sound Hitmarker. sound/");


	g_cBossHud.AddChangeHook(OnConVarChanged);
	g_cBreakableHud.AddChangeHook(OnConVarChanged);
	g_cDamgeHud.AddChangeHook(OnConVarChanged);
	g_cVUpdateTime.AddChangeHook(OnConVarChanged);
	g_cVBossHitmarker.AddChangeHook(OnConVarChanged);
	g_cVZombieHitmarker.AddChangeHook(OnConVarChanged);
	g_cCvarSound.AddChangeHook(OnConVarChanged);
	
	OnConVarChanged(null, "", "");

	AutoExecConfig(true, "Boss_hud");
	InitiateTimer();

	g_bOutputInfo = LibraryExists("OutputInfo");
	SetCookieMenuItem(PrefMenu, 0, "Boss Hud");
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	MarkNativeAsOptional("GetOutputActionValueFloat");
	return APLRes_Success;
}

public void OnLibraryRemoved(const char[] name) {
	if (StrEqual(name, "OutputInfo")) {
		g_bOutputInfo = false;
	}
}
 
public void OnLibraryAdded(const char[] name) {
	if (StrEqual(name, "OutputInfo")) {
		g_bOutputInfo = true;
	}
}

public void PrefMenu(int client, CookieMenuAction actions, any info, char[] buffer, int maxlen)
{
	if(actions == CookieMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlen, "%T", "Cookie_Menu", client);
	}

	if(actions == CookieMenuAction_SelectOption)
	{
		MenuClientBhud(client);
	}
}

public void OnConVarChanged(ConVar CVar, const char[] oldVal, const char[] newVal)
{
	g_bBossHud = g_cBossHud.BoolValue;
	g_bBreakableHud = g_cBreakableHud.BoolValue;
	g_bDamgeHud = g_cDamgeHud.BoolValue;
	g_fVUpdateTime = g_cVUpdateTime.FloatValue;
	g_cVBossHitmarker.GetString(g_sBossHitmarker, sizeof(g_sBossHitmarker));
	g_cVZombieHitmarker.GetString(g_sZombieHitmarker, sizeof(g_sZombieHitmarker));
	g_cCvarSound.GetString(g_sCvarSound, sizeof(g_sCvarSound));
	InitiateTimer();
}

public void InitiateTimer()
{
	if(g_hTimer != INVALID_HANDLE) {
		KillTimer(g_hTimer); 
		g_hTimer = INVALID_HANDLE; 
	}

	if (g_bBossHud || g_bBreakableHud || g_bDamgeHud) g_hTimer = CreateTimer(g_fVUpdateTime, Timer_HUDUpdate, _, TIMER_REPEAT);
}

public void OnConfigsExecuted()
{
	char s_DownloadTable[PLATFORM_MAX_PATH];
	PrecacheDecal(g_sBossHitmarker, true);
	Format(s_DownloadTable, sizeof(s_DownloadTable), "materials/%s", g_sBossHitmarker);
	AddFileToDownloadsTable(s_DownloadTable);

	Format(s_DownloadTable, sizeof(s_DownloadTable), g_sBossHitmarker);
	ReplaceString(s_DownloadTable, sizeof(s_DownloadTable), ".vmt", ".vtf");
	PrecacheDecal(s_DownloadTable, true);
	Format(s_DownloadTable, sizeof(s_DownloadTable), "materials/%s", s_DownloadTable);
	AddFileToDownloadsTable(s_DownloadTable);

	PrecacheDecal(g_sZombieHitmarker, true);
	Format(s_DownloadTable, sizeof(s_DownloadTable), "materials/%s", g_sZombieHitmarker);
	AddFileToDownloadsTable(s_DownloadTable);

	Format(s_DownloadTable, sizeof(s_DownloadTable), g_sZombieHitmarker);
	ReplaceString(s_DownloadTable, sizeof(s_DownloadTable), ".vmt", ".vtf");
	PrecacheDecal(s_DownloadTable, true);
	Format(s_DownloadTable, sizeof(s_DownloadTable), "materials/%s", s_DownloadTable);
	AddFileToDownloadsTable(s_DownloadTable);

	Format(s_DownloadTable, sizeof(s_DownloadTable), "sound/%s", g_sCvarSound);
	AddFileToDownloadsTable(s_DownloadTable);
	PrecacheSound(g_sCvarSound, true);
}

public void OnClientCookiesCached(int client)
{
	strcopy(Clinet_message[client],512, "");
	char scookie[64];

	GetClientCookie(client, g_hHpBhEnable, scookie, sizeof(scookie));
	if(!StrEqual(scookie, ""))
	{
		BossHudClientEnum[client].e_bHpBhEnable = view_as<bool>(StringToInt(scookie));
	}
	else	BossHudClientEnum[client].e_bHpBhEnable = true;
		
	GetClientCookie(client, g_hHpBrEnable, scookie, sizeof(scookie));
	if(!StrEqual(scookie, ""))
	{
		BossHudClientEnum[client].e_bHpBrEnable = view_as<bool>(StringToInt(scookie));
	}
	else	BossHudClientEnum[client].e_bHpBrEnable = false;
	
	GetClientCookie(client, g_hHitmEnable, scookie, sizeof(scookie));
	if(!StrEqual(scookie, ""))
	{
		BossHudClientEnum[client].e_bHitmEnable = view_as<bool>(StringToInt(scookie));
	}
	else	BossHudClientEnum[client].e_bHitmEnable = true;

	GetClientCookie(client, g_hHitmSound, scookie, sizeof(scookie));
	if(!StrEqual(scookie, ""))
	{
		BossHudClientEnum[client].e_bHitmSound = view_as<bool>(StringToInt(scookie));
	}
	else	BossHudClientEnum[client].e_bHitmSound = true;

	GetClientCookie(client, g_hIsHitEnabled, scookie, sizeof(scookie));
	if(!StrEqual(scookie, ""))
	{
		BossHudClientEnum[client].e_bIsHitEnabled = view_as<bool>(StringToInt(scookie));
	}
	else	BossHudClientEnum[client].e_bIsHitEnabled = false;

	g_bIsFired[client] = false;
	didhit[client] = false;
	showhud[client] = false;
}

public void Event_RoundStart(Handle ev, const char[] name, bool broadcast)
{
	LoadConfig();

	if (EntityMaxes != INVALID_HANDLE)
		CloseHandle(EntityMaxes);

	EntityMaxes = CreateTrie();
	ClearTrie(EntityMaxes);

	for(int i = 1; i <= MaxClients; i++) {
		didhit[i] = false;
		showhud[i] = false;
		strcopy(Clinet_message[i],512, "");
		Hitmarker_Reset(i);
	}
}
/*
public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bDamgeHud) return;

	static int iVictim, iAttacker, iDmg, iHitgroup;
	static char sWeapon[16];
	
	if(!(iAttacker = GetClientOfUserId(event.GetInt("attacker"))) || !(iVictim = GetClientOfUserId(event.GetInt("userid")))
	|| iAttacker == iVictim || !BossHudClientEnum[iAttacker].e_bIsHitEnabled || !IsValidClient(iAttacker) || GetClientTeam(iAttacker) != 3)
		return;

	iDmg = event.GetInt("dmg_health");
	iHitgroup = event.GetInt("hitgroup");
	event.GetString("weapon", sWeapon, sizeof(sWeapon));

	if(iHitgroup >= 3)
	{
		g_iColor[iAttacker][0] = 255;
		g_iColor[iAttacker][1] = 255;
		g_iColor[iAttacker][2] = 255;
	}
	else if(iHitgroup >= 2)
	{
		g_iColor[iAttacker][0] = 253;
		g_iColor[iAttacker][1] = 229;
		g_iColor[iAttacker][2] = 0;
	}
	else 
	{
		g_iColor[iAttacker][0] = 255;
		g_iColor[iAttacker][1] = 0;
		g_iColor[iAttacker][2] = 0;
	}

	if(strcmp(sWeapon, "knife"))
	{
		if(!g_bIsFired[iAttacker])
		{
			g_bIsFired[iAttacker] = true;
			g_iTotalSGDamage[iAttacker] = iDmg;
			CreateTimer(0.1, TimerHit_CallBack, GetClientUserId(iAttacker), TIMER_FLAG_NO_MAPCHANGE);
		}
		else g_iTotalSGDamage[iAttacker] += iDmg;
	
		if (BossHudClientEnum[iAttacker].e_bHitmSound) EmitSoundToClient(iAttacker, g_sCvarSound, _, SNDCHAN_AUTO);
		if (BossHudClientEnum[iAttacker].e_bHitmEnable) Hitmarker_StartZombie(iAttacker);
	}
	return;
}*/

public Action TimerHit_CallBack(Handle timer, int userid)
{
	static int iAttacker;
	if(!(iAttacker = GetClientOfUserId(userid)))
		return Plugin_Stop;

	float fPos[2];
	fPos[0] += 0.430 + GetRandomFloat(0.000, 0.020);
	fPos[1] += 0.430 + GetRandomFloat(0.000, 0.020);
	
	ShowDamageText(iAttacker, g_iTotalSGDamage[iAttacker], fPos, g_iColor[iAttacker]);
	g_iTotalSGDamage[iAttacker] = 0;

	return Plugin_Continue;
}

stock int ShowDamageText(int iClient, int iDmg, float[] fPos, int[] iColor)
{
	SetHudTextParams(fPos[0], fPos[1], 0.1, iColor[0], iColor[1], iColor[2], 200, 1);
	ShowHudText(iClient, -1, "%i", iDmg);
	g_bIsFired[iClient] = false;
}

void LoadConfig(int id = -1)
{
	g_iBosses = 0;
	g_iMultShowing = 0;

	char mapname[128], filename[256];
	GetCurrentMap(mapname, sizeof(mapname));
	Format(filename, sizeof(filename), "addons/sourcemod/configs/Boss_Hud/%s.txt", mapname);

	KeyValues kv = new KeyValues("File");
	kv.ImportFromFile(filename);

	if (!kv.GotoFirstSubKey()) {
		delete kv;
		return;
	}

   	// default values
	g_bShowTopDMG   = true;
	g_bMultBoss	 = false;
	g_bMultHP		= false;

	do {
		if(id != -1 && id != g_iBosses) {
			g_iBosses++;
			continue;
		}

		char section[64];
		kv.GetSectionName(section, sizeof(section));

		if (StrEqual(section, "config")) {
			g_bShowTopDMG   = (kv.GetNum("BossBeatenShowTopDamage", g_bShowTopDMG) == 1);
			g_bMultBoss	 = (kv.GetNum("MultBoss", g_bMultBoss) == 1);
			g_bMultHP		= (kv.GetNum("MultHP", g_bMultHP) == 1);
			continue;
		}

		kv.GetString("HP_counter",	  bosses[g_iBosses].szTargetName, BOSS_NAME_LEN, bosses[g_iBosses].szTargetName);
		kv.GetString("BreakableName",   bosses[g_iBosses].szTargetName, BOSS_NAME_LEN, bosses[g_iBosses].szTargetName);

		kv.GetString("CustomText", 		bosses[g_iBosses].szDisplayName, BOSS_NAME_LEN, bosses[g_iBosses].szTargetName);

		kv.GetString("HPbar_counter",   bosses[g_iBosses].szHPBarName,  BOSS_NAME_LEN, bosses[g_iBosses].szHPBarName);
		kv.GetString("HPinit_counter",  bosses[g_iBosses].szHPInitName, BOSS_NAME_LEN, bosses[g_iBosses].szHPInitName);

		bosses[g_iBosses].iMaxBars	  = kv.GetNum("HPbar_max",		10); //now basing it off of current bars on first activation (IF BAR TYPE == DECREASING)
		bosses[g_iBosses].iCurrentBars  = kv.GetNum("HPbar_default",	0);
		bosses[g_iBosses].iForceBars	= kv.GetNum("HPbar_force",	  0);

		int iBarMode = kv.GetNum("HPbar_mode", 0);
		if(iBarMode == 1)
			bosses[g_iBosses].hpBarMode = decreasing;
		else if(iBarMode == 2) {
			bosses[g_iBosses].hpBarMode = increasing;
			bosses[g_iBosses].iCurrentBars = bosses[g_iBosses].iMaxBars - bosses[g_iBosses].iCurrentBars;
		}
		else
			bosses[g_iBosses].hpBarMode = none;

		bosses[g_iBosses].bDead = false;
		bosses[g_iBosses].bDeadInit = false;
		bosses[g_iBosses].bActive = false;

		bosses[g_iBosses].iBossEnt	   = -1;
		bosses[g_iBosses].iHPCounterEnt  = -1;
		bosses[g_iBosses].iInitEnt	   = -1;

		for(int i = 0; i <= MaxClients; i++) {
			bosses[g_iBosses].iDamage[i] = 0;
		}

		bosses[g_iBosses].iTotalHits 	= 0;
		bosses[g_iBosses].iLastHit 		= -1;
		bosses[g_iBosses].iFirstActive 	= -1;

		g_iBosses++;
	} while (kv.GotoNextKey());
	
	delete kv;
}

stock int GetCounterValue(int counter) {
	char szType[64];
	GetEntityClassname(counter, szType, sizeof(szType));

	if(!StrEqual(szType, "math_counter", false)) {
		return -1;
	}

	if(g_iOutValueOffset == -1)
		g_iOutValueOffset = FindDataMapInfo(counter, "m_OutValue");

	if(g_bOutputInfo)
		return RoundFloat(GetOutputActionValueFloat(counter, "m_OutValue"));
	return RoundFloat(GetEntDataFloat(counter, g_iOutValueOffset));
}

stock bool IsValidClient(int client) {
	if (!(1 <= client <= MaxClients) || !IsClientInGame(client))
		return false;
	return true;
}

public Action Command_ToggleBHUD(int client, int argc)
{
	if(IsValidClient(client))
	{
		MenuClientBhud(client);
	}
	return Plugin_Handled;
}

public Action Command_BhudDebug(int client, int argc)
{
	if(IsValidClient(client))
	{
		if (g_bBoshudDebugger[client])
		{
			g_bBoshudDebugger[client] = false;
			CPrintToChat(client, "%t", "Boshud Debugger Desabled");
		}
		else
		{
			g_bBoshudDebugger[client] = true;
			CPrintToChat(client, "%t", "Boshud Debugger Enabled");
		}
	}
	else
	PrintToChat(client, "%t", "No Access");
	return Plugin_Handled;
}

void MenuClientBhud(int client)
{
	if (!IsValidClient(client))
	{
		return;
	}
	SetGlobalTransTarget(client);

	/*char m_sTitle[256];
	char m_sBoss_Hud[64];
	char m_sBrekable_Hud[64];
	char m_sBoss_Hit_Marker[64];
	char m_sBoss_Hits_Sound[64];
	char m_sBoss_Hits_Zombie[64];*/

	char m_sBoss_HudTemp[64];
	char m_sBrekable_HudTemp[64];
	char m_sBoss_Hit_MarkerTemp[64];
	char m_sBoss_Hits_SoundTemp[64];
	//char m_sBoss_Hits_ZombieTemp[64];

	if (BossHudClientEnum[client].e_bHpBhEnable) Format(m_sBoss_HudTemp ,sizeof(m_sBoss_HudTemp) ,"Boss Hud Damage: %t" ,"Enabled" );
	else Format(m_sBoss_HudTemp ,sizeof(m_sBoss_HudTemp) ,"Boss Hud Damage: %t" ,"Desabled" );

	if (BossHudClientEnum[client].e_bHpBrEnable) Format(m_sBrekable_HudTemp ,sizeof(m_sBrekable_HudTemp) ,"Brekable Hud: %t" ,"Enabled" );
	else Format(m_sBrekable_HudTemp ,sizeof(m_sBrekable_HudTemp) ,"Brekable Hud: %t" ,"Desabled" );

	if (BossHudClientEnum[client].e_bHitmEnable) Format(m_sBoss_Hit_MarkerTemp ,sizeof(m_sBoss_Hit_MarkerTemp) ,"Boss Hit Marker: %t" ,"Enabled" );
	else Format(m_sBoss_Hit_MarkerTemp ,sizeof(m_sBoss_Hit_MarkerTemp) ,"Boss Hit Marker: %t" ,"Desabled" );

	if (BossHudClientEnum[client].e_bHitmSound) Format(m_sBoss_Hits_SoundTemp ,sizeof(m_sBoss_Hits_SoundTemp) ,"Boss Hit Sounds: %t" ,"Enabled" );
	else Format(m_sBoss_Hits_SoundTemp ,sizeof(m_sBoss_Hits_SoundTemp) ,"Boss Hit Sounds: %t" ,"Desabled" );

	//if (BossHudClientEnum[client].e_bIsHitEnabled) Format(m_sBoss_Hits_ZombieTemp ,sizeof(m_sBoss_Hits_ZombieTemp) ,"Zombies Hud Hits: %t" ,"Enabled" );
	//else Format(m_sBoss_Hits_ZombieTemp ,sizeof(m_sBoss_Hits_ZombieTemp) ,"Zombies Hud Hits: %t" ,"Desabled" );

	/*Format(m_sTitle ,sizeof(m_sTitle) ,"%t" ,"Boss Hud Title" ,m_sBoss_HudTemp, m_sBrekable_HudTemp, m_sBoss_Hit_MarkerTemp, m_sBoss_Hits_SoundTemp, m_sBoss_Hits_ZombieTemp);
	
	Format(m_sBoss_Hud, sizeof(m_sBoss_Hud), "%t", "Boss Hud Damage");
	Format(m_sBrekable_Hud, sizeof(m_sBrekable_Hud), "%t", "Brekable Hud");
	Format(m_sBoss_Hit_Marker, sizeof(m_sBoss_Hit_Marker), "%t", "Boss Hit Marker");
	Format(m_sBoss_Hits_Sound, sizeof(m_sBoss_Hits_Sound), "%t", "Zombies Hit Sounds");
	Format(m_sBoss_Hits_Zombie, sizeof(m_sBoss_Hits_Zombie), "%t", "Zombies Hud Hits");*/

	Menu MenuBhud = new Menu(MenuClientBhudCallBack);

	MenuBhud.ExitBackButton = true;
	MenuBhud.SetTitle("Boss Hud");

	MenuBhud.AddItem("Boss_Hud_Enable", m_sBoss_HudTemp, MenuGetItemDraw(g_bBossHud));
	MenuBhud.AddItem("Brekable_Hud_Enable", m_sBrekable_HudTemp, MenuGetItemDraw(g_bBreakableHud));
	MenuBhud.AddItem("Boss_Hit_Marker_Enable", m_sBoss_Hit_MarkerTemp);
	MenuBhud.AddItem("Boss_Hits_Sound_Enable", m_sBoss_Hits_SoundTemp);
	//MenuBhud.AddItem("Boss_Hits_Zombie_Enable", m_sBoss_Hits_ZombieTemp, MenuGetItemDraw(g_bDamgeHud));

	MenuBhud.Display(client, MENU_TIME_FOREVER);
}

public int MenuClientBhudCallBack(Handle MenuBhud, MenuAction action, int client, int itemNum)
{
	if (action == MenuAction_End)
	{
		delete MenuBhud;
	}

	if (action == MenuAction_Select)
    {
		char sItem[64];
		GetMenuItem(MenuBhud, itemNum, sItem, sizeof(sItem));
		if (StrEqual(sItem[0], "Boss_Hud_Enable"))
		{
			BossHudClientEnum[client].e_bHpBhEnable = !BossHudClientEnum[client].e_bHpBhEnable;
			BossHudCookiesSetBool(client, g_hHpBhEnable, BossHudClientEnum[client].e_bHpBhEnable);
			MenuClientBhud(client);
		}
		else if (StrEqual(sItem[0], "Brekable_Hud_Enable"))
		{
			BossHudClientEnum[client].e_bHpBrEnable = !BossHudClientEnum[client].e_bHpBrEnable;
			BossHudCookiesSetBool(client, g_hHpBrEnable, BossHudClientEnum[client].e_bHpBrEnable);
			MenuClientBhud(client);
		}
		else if (StrEqual(sItem[0], "Boss_Hit_Marker_Enable"))
		{
			BossHudClientEnum[client].e_bHitmEnable = !BossHudClientEnum[client].e_bHitmEnable;
			BossHudCookiesSetBool(client, g_hHitmEnable, BossHudClientEnum[client].e_bHitmEnable);
			MenuClientBhud(client);
		}

		else if (StrEqual(sItem[0], "Boss_Hits_Sound_Enable"))
		{
			BossHudClientEnum[client].e_bHitmSound = !BossHudClientEnum[client].e_bHitmSound;
			BossHudCookiesSetBool(client, g_hHitmSound, BossHudClientEnum[client].e_bHitmSound);
			MenuClientBhud(client);
		}
		/*else if (StrEqual(sItem[0], "Boss_Hits_Zombie_Enable"))
		{
			BossHudClientEnum[client].e_bIsHitEnabled = !BossHudClientEnum[client].e_bIsHitEnabled;
			BossHudCookiesSetBool(client, g_hIsHitEnabled, BossHudClientEnum[client].e_bIsHitEnabled);
			MenuClientBhud(client);
		}*/
 	}

	if (action == MenuAction_Cancel)
	{
		if(itemNum == MenuCancel_ExitBack) ShowCookieMenu(client);
	}

	return 0;
}

stock int MenuGetItemDraw(bool condition)
{
	return condition ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED;
}

void BossHudCookiesSetBool(int client, Handle cookie, bool cookievalue)
{
	char strCookievalue[8];
	BoolToString(cookievalue, strCookievalue, sizeof(strCookievalue));

	SetClientCookie(client, cookie, strCookievalue);
}

void BoolToString(bool value, char[] output, int maxlen)
{
	if(value) strcopy(output, maxlen, "1");
	else strcopy(output, maxlen, "0");
}

public void Output_OnHealthChanged(const char[] output, int caller, int activator, float delay)
{
	if (!g_bBreakableHud) return;
	char szName[64];
	GetEntPropString(caller, Prop_Data, "m_iName", szName, sizeof(szName));

	if (IsValidClient(activator))
	{
		didhit[activator] = true;
		showhud[activator] = true;
		if (g_bBoshudDebugger[activator])
		{
			int hammerIDi = GetEntProp(caller, Prop_Data, "m_iHammerID");
			int HPvalue = GetEntProp(caller, Prop_Data, "m_iHealth");
			PrintToChat(activator, " \x04[Boss_HUD] Breakable: \x01%s  \x04HammerID: \x01%d  \x04HP: \x01%d\x04.", szName, hammerIDi, HPvalue);
		}
	}

	for (int i = 0; i < g_iBosses; i++) {
		if (StrEqual(bosses[i].szTargetName, szName, false)) {
			if(bosses[i].bDead)
				return;

			int hp = GetEntProp(caller, Prop_Data, "m_iHealth");

			if(hp > MAX_BREAKABLE_HP)
				return;

			if(hp > bosses[i].iHighestHP)
				bosses[i].iHighestHP = hp;

			// HP AND PERCENTAGE RECALIBRATION
			int percentLeft = RoundFloat((hp * 1.0 / bosses[i].iHighestHP) * 100); // if percentLeft <= 75 within the first 3 seconds, reset it
			if(GetTime() - bosses[i].iFirstActive <= 3 && percentLeft <= 75) {
				bosses[i].iHighestHP = hp;
			}
			if(percentLeft == 0 && hp >= 1000) { // if 0 percent left and hp >= 1000, reset it
				bosses[i].iHighestHP = hp;
			}

			bosses[i].iHP = hp;
			bosses[i].iBossEnt = caller;

			if (IsValidClient(activator)) {

				if(bosses[i].iTotalHits > 5) {
					if(bosses[i].iFirstActive == -1)
						bosses[i].iFirstActive = GetTime();

					bosses[i].bActive = true;
				}

				bosses[i].iLastHit = GetTime();

				if (BossHudClientEnum[activator].e_bHitmEnable) Hitmarker_StartBoss(activator);
				bosses[i].iDamage[activator] += 1;
				bosses[i].iTotalHits += 1;

				AddClientMoney(activator, 20);

				if(hp <= 0 && bosses[i].hpBarMode == none) {
					bosses[i].bDead = true;
					bosses[i].bDeadInit = true;
				}
			}

			return;
		}
	}

	if (IsValidClient(activator)) {
		if (BossHudClientEnum[activator].e_bHpBrEnable)
		{
			simplehud.iEntID[activator] = caller;
			simplehud.iTimer[activator] = GetTime();
		}
		if (BossHudClientEnum[activator].e_bHitmEnable) Hitmarker_StartBoss(activator);
	}
}

public void Output_OnBreak(const char[] output, int caller, int activator, float delay)
{
	for (int i = 0; i < g_iBosses; i++) {
		if(bosses[i].iBossEnt == caller) {
			bosses[i].iHP	   = 0;
			bosses[i].bDead	 = true;
			bosses[i].bDeadInit  = true;
		}
	}
}

public void Output_OutValue(const char[] output, int caller, int activator, float delay)
{
	if (!g_bBossHud) return;
	char szName[64];
	GetEntPropString(caller, Prop_Data, "m_iName", szName, sizeof(szName));

	if(IsValidClient(activator))
	{
		if (BossHudClientEnum[activator].e_bHpBhEnable)
		{
			simplehud.iEntID[activator] = caller;
			simplehud.iTimer[activator] = GetTime();
		}
		if (BossHudClientEnum[activator].e_bHitmEnable) Hitmarker_StartBoss(activator);
		if (BossHudClientEnum[activator].e_bHitmSound) EmitSoundToClient(activator, g_sCvarSound, _, SNDCHAN_AUTO);
		didhit[activator] = true;
		showhud[activator] = true;
		if (g_bBoshudDebugger[activator])
		{
			int hammerIDi = GetEntProp(caller, Prop_Data, "m_iHammerID");
			int HPvalue = RoundToNearest(GetEntDataFloat(caller, FindDataMapInfo(caller, "m_OutValue")));
			PrintToChat(activator, " \x04[Boss_HUD] MathCounter: \x01%s  \x04HammerID: \x01%d  \x04HP: \x01%d\x04.", szName, hammerIDi, HPvalue);
		}
	}

	for (int i = 0; i < g_iBosses; i++) {
		if (StrEqual(bosses[i].szTargetName, szName, false)) {
			if(bosses[i].bDead)
				return;

			int counter = GetCounterValue(caller);
			int hp = counter;
			bosses[i].iBossEnt = caller;

			int min = RoundFloat(GetEntPropFloat(caller, Prop_Data, "m_flMin"));
			int max = RoundFloat(GetEntPropFloat(caller, Prop_Data, "m_flMax"));

			if(bosses[i].hpMode == increasing) {
				hp = max - hp;
			}

			bosses[i].iHP = hp;

			if(hp > bosses[i].iHighestHP)
				bosses[i].iHighestHP = hp;

			// HP AND PERCENTAGE RECALIBRATION
			if(bosses[i].hpBarMode != none) {
				if(hp > 25 && (bosses[i].iHighestHP*1.0) / hp > 150.0) { // if iHighestHP seems too large for a segment, reset it
					bosses[i].iHighestHP = hp;
					bosses[i].iHighestTotalHP = 0;
				}
			}
			else {
				int percentLeft = RoundFloat((hp * 1.0 / bosses[i].iHighestHP) * 100); // if percentLeft <= 75 within the first 3 seconds, reset it
				if(GetTime() - bosses[i].iFirstActive <= 3 && percentLeft <= 75) {
					bosses[i].iHighestHP = hp;
				}
			}

			if(IsValidClient(activator)) {
				if(bosses[i].hpBarMode == none) {
					if(bosses[i].bActive && bosses[i].iTotalHits > 5) {
						if((bosses[i].hpMode == decreasing && hp <= min) || (bosses[i].hpMode == increasing && counter >= max)) {
							bosses[i].bDead	 = true;
							bosses[i].bDeadInit = true;
						}
					}
				}

				AddClientMoney(activator, 20);
				if (BossHudClientEnum[activator].e_bHitmEnable) Hitmarker_StartBoss(activator);

				bosses[i].iDamage[activator] += 1;
				bosses[i].iTotalHits += 1;

				if(bosses[i].iTotalHits > 5) {
					if(bosses[i].iFirstActive == -1)
						bosses[i].iFirstActive = GetTime();

					bosses[i].bActive = true;
				}

				bosses[i].iLastHit = GetTime();
			}

			return;
		}
		else if(StrEqual(bosses[i].szHPBarName, szName, false)) {
			if(bosses[i].bDead)
				return;

			int barCount = GetCounterValue(caller);

			if(bosses[i].hpBarMode == increasing)
				barCount = bosses[i].iMaxBars - barCount;

			bosses[i].iHPCounterEnt = caller;

			if(IsValidClient(activator)) {
				if(bosses[i].bActive && barCount == 0) {
					bosses[i].bDead	 = true;
					bosses[i].bDeadInit  = true;
				}

				bosses[i].iCurrentBars = barCount;

				
				if(!bosses[i].bActive) {
					if(bosses[i].hpBarMode == decreasing)
						bosses[i].iMaxBars = barCount;
				}
				else {
				   if(bosses[i].iMaxBars == 0) {
						if(bosses[i].hpBarMode == decreasing) // if no HPBar set, set max to current +1 (bc this only triggers on decrease)
							bosses[i].iMaxBars = barCount + 1;
					} 
				}

				bosses[i].iLastHit = GetTime();
			}

			return;
		}
		else if(StrEqual(bosses[i].szHPInitName, szName, false)) {
			if(bosses[i].bDead)
				return;

			bosses[i].iInitHP = GetCounterValue(caller);
			bosses[i].iInitEnt = caller;

			return;
		}
	}
}

public void OnEntityCreated(int entity, const char[] classname) {
	if (IsValidEntity(entity)) {
		SDKHook(entity, SDKHook_SpawnPost, OnEntitySpawnPost);
	}
}

public void OnEntitySpawnPost(int ent) {
	RequestFrame(CheckEnt, ent);
}

public void CheckEnt(any ent) {
	if (IsValidEntity(ent)) {
		char szName[64], szType[64];
		GetEntityClassname(ent, szType, sizeof(szType));
		GetEntPropString(ent, Prop_Data, "m_iName", szName, sizeof(szName));

		if (StrEqual(szType, "math_counter", false)) {
			SetTrieValue(EntityMaxes, szName, RoundFloat(GetEntPropFloat(ent, Prop_Data, "m_flMax")), true);
		}
	}
}

stock int GetClientMoney(int client) {
	return GetEntProp(client, Prop_Send, "m_iAccount");
}
stock void SetClientMoney(int client, int money) {
	SetEntProp(client, Prop_Send, "m_iAccount", money);
}
stock void AddClientMoney(int client, int money) {
	SetClientMoney(client, GetClientMoney(client) + money);
}

stock void StringEllipser(char[] szMessage, int cutoff) {
	if(strlen(szMessage) > cutoff) {
		szMessage[cutoff] = '.';
		szMessage[cutoff+1] = '.';
		szMessage[cutoff+2] = '.';
		szMessage[cutoff+3] = '\0';
	}
}/*
public Action EWM_Hud_Timer_DisplayHUD(Handle timer)
{
	ServerCommand("sm_resettimer");
}*/
public Action Timer_HUDUpdate(Handle timer) {
	/*if(!starttimer)
	{
		CreateTimer(0.77, EWM_Hud_Timer_DisplayHUD, _, TIMER_FLAG_NO_MAPCHANGE);
		//ServerCommand("sm_resettimer");
		starttimer = true;
	}*/
	bool inConfig = false;
	for(int i = 0; i < g_iBosses; i++) {
		if(IsValidBoss(i)) {
			inConfig = true;
			break;
		}
	}

	for(int i = 1; i <= MaxClients; i++) {
		if(IsValidClient(i) && g_iHitmarkerTime[i] != -1 && GetTime() >= g_iHitmarkerTime[i]) {
			Hitmarker_Reset(i);
		}
	}

	if(!inConfig) {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsValidClient(i) && BossHudClientEnum[i].e_bHpBrEnable) {
				HUD_SimpleUpdate(i);
			}
		}
		return Plugin_Continue;
	}

	char message[512];
	if(g_bMultBoss) {
		int count = 0;
		for(int i = 0; i < g_iBosses; i++) {
			if(IsValidBoss(i)) {
				count++;
			}
		}

		int[] bossIds = new int[count];
		for(int i = 0, j = 0; i < g_iBosses; i++) {
			if(IsValidBoss(i)) {
				bossIds[j++] = i;
			}
		}

		if(GetTime() > g_iMultLastSwitch + DELAY_MULTBOSS) {
			g_iMultShowing++;
			g_iMultLastSwitch = GetTime();
		}
		if(g_iMultShowing >= count) {
			g_iMultShowing = 0;
		}

		bool bForceUpdate = false;

		for(int i = 0; i < g_iBosses; i++) {
			if(bosses[i].bActive && bosses[i].bDead && bosses[i].bDeadInit) {
				HUD_Update(i, message, sizeof(message));
				bForceUpdate = true;
				break;
			}
		}

		if(!bForceUpdate)
			HUD_Update(bossIds[g_iMultShowing], message, sizeof(message));
	}
	else {
		for(int i = 0; i < g_iBosses; i++) {
			if(IsValidBoss(i)) {
				HUD_Update(i, message, sizeof(message));
				break;
			}
		}
	}

	if (strlen(message) != 0) {
		for (int client = 1; client <= MaxClients; client++) {
			if (IsClientInGame(client) && BossHudClientEnum[client].e_bHpBhEnable && didhit[client]) {
				strcopy(Clinet_message[client],512, message);
				PrintHintText(client, "%s", message);
				didhit[client] = false;
				showhud[client] = true;
				if(HitTimer[client] != null)
					KillTimer(HitTimer[client]);

				HitTimer[client] = CreateTimer(1.1, Timer_HitTimer,client);
			}
		}
	}
	return Plugin_Continue;
}

public Action Timer_HitTimer(Handle timer, int client)
{
	//PrintToChatAll("RESET %N",client);
	showhud[client] = false;
	HitTimer[client] = null;
}

public void OnClientDisconnect(int client)
{
	if(!IsFakeClient(client))
	{
		delete HitTimer[client];
	}
}

public Action OnPlayerRunCmd( int client )
{
	if(showhud[client])
	{
		if (StrEqual(Clinet_message[client], ""))
			showhud[client] = false;

		PrintHintText(client, "%s", Clinet_message[client]);
	}
}

stock bool IsValidBoss(int i) {
	if(bosses[i].bActive) {
		if((bosses[i].bDead && GetTime() < bosses[i].iLastHit + DELAY_BOSSDEAD) || (!bosses[i].bDead && GetTime() < bosses[i].iLastHit + DELAY_BOSSTIMEOUT)) {
			return true;
		}
	}
	return false;
}

public void HUD_Update(int i, char[] message, int len) {
	if(!bosses[i].bActive)
		return;

	if(bosses[i].bDead) {
		if(GetTime() < bosses[i].iLastHit + DELAY_BOSSDEAD) {
			HUD_BossDead(i, message, len);
		}
	}
	else if (GetTime() < bosses[i].iLastHit + DELAY_BOSSTIMEOUT) {
		if(bosses[i].hpBarMode == none) {
			if(bosses[i].iForceBars == 0) {
				HUD_BossNoBars(i, message, len);
			}
			else
				HUD_BossForceBars(i, message, len);
		}
		else {
			HUD_BossWithBars(i, message, len);
		}
	}
}

public void HUD_SimpleUpdate(int client) {
	int ent = simplehud.iEntID[client];
	int time = simplehud.iTimer[client];

	if(IsValidEntity(ent) && (GetTime() - time) < DELAY_SIMPLEHUD) {
		char szName[64], szType[64];
		int health;

		GetEntityClassname(ent, szType, sizeof(szType));
		GetEntPropString(ent, Prop_Data, "m_iName", szName, sizeof(szName));

		if(strlen(szName) == 0)
			Format(szName, sizeof(szName), "Health");

		if(StrEqual(szType, "math_counter", false)) {
			health = GetCounterValue(ent);

			int max;
			if(GetTrieValue(EntityMaxes, szName, max) && max != RoundFloat(GetEntPropFloat(ent, Prop_Data, "m_flMax")))
				health = RoundFloat(GetEntPropFloat(ent, Prop_Data, "m_flMax")) - health;
		}
		else
			health = GetEntProp(ent, Prop_Data, "m_iHealth");

		if(health <= 0 || health > MAX_BREAKABLE_HP)
			return;

		char szMessage[128];
		/*char colorh[8];
		if(health >= 66) colorh = "00FF00";
		else if(health >= 33) colorh = "ffff00";
		else colorh = "ff0000";

		Format(szMessage, sizeof(szMessage), "►[<font color='" ... COLOR_SIMPLEHUD ... "'>%s</font>]◄ HP: <font class='fontSize-xl' font color='#%s'>%d</font>", szName, colorh, health);
		*/
		Format(szMessage, sizeof(szMessage), "<font class='fontSize-l'> %s \n Életerö: %d \n</font>",szName, health);
		strcopy(Clinet_message[client],512, szMessage);
		PrintHintText(client, "%s", szMessage);
	}
}

public void HUD_BossDead(int id, char[] szMessage, int len) {
	if(g_bShowTopDMG) {
		int one = 0, two = 0, three = 0;
		for (int i = 1; i <= MaxClients; i++) {
			if (bosses[id].iDamage[i] > bosses[id].iDamage[one]) {
				three = two;
				two = one;
				one = i;
			} else if (bosses[id].iDamage[i] > bosses[id].iDamage[two]) {
				three = two;
				two = i;
			} else if (bosses[id].iDamage[i] > bosses[id].iDamage[three]) {
				three = i;
			}

			if(IsClientInGame(i) && bosses[id].iDamage[i] > 5) {
				SetHudTextParams(-1.0, 0.9, 3.0, 255,255, 0, 255);
				ShowHudText(i, -1, "Your damage: %i hits", bosses[id].iDamage[i]);
			}
		}

		char message[512];
		if (one != 0 && bosses[id].iDamage[one] > 5) {
			StrCat(message, sizeof(message), "<font class='fontSize-xl' color='" ... COLOR_TOPBOSSDMG ..."'>TOP BOSS DAMAGE:</font>");

			if(bosses[id].bDeadInit)
				CPrintToChatAll("{red}TOP BOSS DAMAGE:");

			char template[64], name[32];
			GetClientName(one, name, sizeof(name));
			StringEllipser(name, 12);

			Format(template, sizeof(template), "<br>1. %s - %d hits", name, bosses[id].iDamage[one]);
			StrCat(message, sizeof(message), template);

			if(bosses[id].bDeadInit)
				CPrintToChatAll("1. {green}%N{default} - {red}%d{default} hits", one, bosses[id].iDamage[one]);

			if (one != two && two != 0 && bosses[id].iDamage[two] > 5) {
				GetClientName(two, name, sizeof(name));
				StringEllipser(name, 12);

				Format(template, sizeof(template), "<br>2. %s - %d hits", name, bosses[id].iDamage[two]);
				StrCat(message, sizeof(message), template);

				if(bosses[id].bDeadInit)
					CPrintToChatAll("2. {green}%N{default} - {red}%d{default} hits", two, bosses[id].iDamage[two]);

				if (two != three && three != 0 && bosses[id].iDamage[three] > 5) {
					GetClientName(three, name, sizeof(name));
					StringEllipser(name, 12);

					Format(template, sizeof(template), "<br>3. %s - %d hits", name, bosses[id].iDamage[three]);
					StrCat(message, sizeof(message), template);

					if(bosses[id].bDeadInit)
						CPrintToChatAll("3. {green}%N{default} - {red}%d{default} hits", three, bosses[id].iDamage[three]);
				}
			}
		}
		else
			Format(message, sizeof(message), "<br><font class='fontSize-xl' color='" ... COLOR_BOSSNAME ... "'>%s</font> has been killed", bosses[id].szDisplayName);
		
		StrCat(szMessage, len, message);
	}
	else {
		char message[75 + BOSS_NAME_LEN];
		Format(message, sizeof(message), "<br><font class='fontSize-xl' color='" ... COLOR_BOSSNAME ... "'>%s</font> has been killed", bosses[id].szDisplayName);
		StrCat(szMessage, len, message);
	}

	if(bosses[id].bDeadInit) {
		bosses[id].bDeadInit = false;
		CreateTimer(DELAY_BOSSDEAD + 6.0, Timer_ResetBoss, id);
	}

	return;
}

public Action Timer_ResetBoss(Handle timer, int id) {
	ResetBoss(id);
}

public void ResetBoss(int id) {
	bosses[id].iTotalHits = 0; // stop it from reactivating in the future
	if(g_bMultHP) {
		LoadConfig(id);
	}
}

public void HUD_BossNoBars(int id, char[] szMessage, int len) {
	int percentLeft = RoundFloat((bosses[id].iHP * 1.0 / bosses[id].iHighestHP) * 100);
	char message[256];
	if(percentLeft > 200 || percentLeft < 0) {
		/*char colorh[8];
		if(bosses[id].iHP >= 66) colorh = "00FF00";
		else if(bosses[id].iHP >= 33) colorh = "ffff00";
		else colorh = "ff0000";

		Format(message, sizeof(message), "►[<font color='" ... COLOR_BOSSNAME ... "'>%s</font>]◄ HP: <font class='fontSize-xl' font color='#%s'>%d</font>", bosses[id].szDisplayName, colorh, bosses[id].iHP);
		*/
		Format(message, sizeof(message), "<font class='fontSize-l'> %s \n Életerö: %d \n</font>",bosses[id].szDisplayName, bosses[id].iHP);
	}
	else {
		if(percentLeft > 100)
			percentLeft = 100;

		/*char colorh[8];
		if(percentLeft >= 66) colorh = "00FF00";
		else if(percentLeft >= 33) colorh = "ffff00";
		else colorh = "ff0000";

		Format(message, sizeof(message), "►[<font color='" ... COLOR_BOSSNAME ... "'>%s</font>]◄ [%d%%] HP: <font class='fontSize-xl' font color='#%s'>%d</font>", bosses[id].szDisplayName, percentLeft, colorh, bosses[id].iHP);
		*/
		Format(message, sizeof(message), "<font class='fontSize-l'> %s \n Életerö: %d | %d%% | \n</font>",bosses[id].szDisplayName, bosses[id].iHP, percentLeft);
	}

	StrCat(szMessage, len, message);
}

public void HUD_BossForceBars(int id, char[] szMessage, int len) {
	int percentLeft = RoundFloat((bosses[id].iHP * 1.0 / bosses[id].iHighestHP) * 100);
	int forceBars = bosses[id].iForceBars;

	char circleClass[32];
	if (forceBars > 32)
		Format(circleClass, sizeof(circleClass), "fontSize-l");
	else
		Format(circleClass, sizeof(circleClass), "fontSize-xl");

	int barCount = RoundToFloor(forceBars * (bosses[id].iHP * 1.0 / bosses[id].iHighestHP));

	char circleColor[32];
	if(percentLeft >= 40)
		Format(circleColor, sizeof(circleColor), COLOR_CIRCLEHI);
	else if(percentLeft >= 15)
		Format(circleColor, sizeof(circleColor), COLOR_CIRCLEMID);
	else
		Format(circleColor, sizeof(circleColor), COLOR_CIRCLELOW);

	char message[512];
	if(percentLeft > 200 || percentLeft < 0) {
		/*char colorh[8];
		if(bosses[id].iHP >= 66) colorh = "00FF00";
		else if(bosses[id].iHP >= 33) colorh = "ffff00";
		else colorh = "ff0000";
		Format(message, sizeof(message), "►[<font color='" ... COLOR_BOSSNAME ... "'>%s</font>]◄ HP: <font class='fontSize-xl' font color='#%s'>%d</font>\n<font class='%s' color='%s'>", bosses[id].szDisplayName, colorh, bosses[id].iHP, circleClass, circleColor);
		*/
		Format(message, sizeof(message), "<font class='fontSize-l'>%s \n Életerö: %d \n",bosses[id].szDisplayName, bosses[id].iHP);
	}
	else {
		if(percentLeft > 100)
			percentLeft = 100;

		/*char colorh[8];
		if(percentLeft >= 66) colorh = "00FF00";
		else if(percentLeft >= 33) colorh = "ffff00";
		else colorh = "ff0000";
		Format(message, sizeof(message), "►[<font color='" ... COLOR_BOSSNAME ... "'>%s</font>]◄ [%d%%%%] HP: <font class='fontSize-xl' font color='#%s'>%d</font>\n<font class='%s' color='%s'>", bosses[id].szDisplayName, percentLeft, colorh, bosses[id].iHP, circleClass, circleColor);
		*/
		Format(message, sizeof(message), "<font class='fontSize-l'>%s \n Életerö: %d | %d%% | \n",bosses[id].szDisplayName, bosses[id].iHP,percentLeft);
	}

	for (int i = 0; i < barCount; i++)
		StrCat(message, sizeof(message), " ✦");
	for (int i = 0; i < forceBars - barCount; i++)
		StrCat(message, sizeof(message), " ✧");

	StrCat(message, sizeof(message), "</font>");

	StrCat(szMessage, len, message);
}

public void HUD_BossWithBars(int id, char[] szMessage, int len) {
	int barsRemaining = bosses[id].iCurrentBars - 1;
	if (barsRemaining < 0)
		barsRemaining = 0;

	char circleClass[32];
	if (bosses[id].iMaxBars > 32)
		Format(circleClass, sizeof(circleClass), "fontSize-l");
	else
		Format(circleClass, sizeof(circleClass), "fontSize-xl");

	int totalHP = 0, percentLeft = 0;
	if (bosses[id].iInitHP != 0) {
		totalHP = bosses[id].iHP + (barsRemaining * bosses[id].iInitHP);
		percentLeft = RoundFloat((totalHP * 1.0 / (bosses[id].iMaxBars * bosses[id].iInitHP)) * 100);
	}
	else {
		totalHP = bosses[id].iHP + (barsRemaining * bosses[id].iHighestHP);
		if(totalHP > bosses[id].iHighestTotalHP)
			bosses[id].iHighestTotalHP = totalHP;
		percentLeft = RoundFloat((totalHP * 1.0 / bosses[id].iHighestTotalHP) * 100);
	}

	/*char circleColor[32];
	if(percentLeft >= 40)
		Format(circleColor, sizeof(circleColor), COLOR_CIRCLEHI);
	else if(percentLeft >= 15)
		Format(circleColor, sizeof(circleColor), COLOR_CIRCLEMID);
	else
		Format(circleColor, sizeof(circleColor), COLOR_CIRCLELOW);
	*/
	char message[512];
	if(percentLeft > 200 || percentLeft < 0) {
		/*char colorh[8];
		if(totalHP >= 66) colorh = "00FF00";
		else if(totalHP >= 33) colorh = "ffff00";
		else colorh = "ff0000";
		Format(message, sizeof(message), "►[<font color='" ... COLOR_BOSSNAME ... "'>%s</font>]◄ HP: <font class='fontSize-xl' font color='#%s'>%d</font>\n<font class='%s' color='%s'>", bosses[id].szDisplayName, colorh, totalHP, circleClass, circleColor);
		*/
		Format(message, sizeof(message), "<font class='fontSize-l'> %s \n Életerö: %d \n",bosses[id].szDisplayName, totalHP );
	}
	else {
		if(percentLeft > 100)
			percentLeft = 100;

		/*char colorh[8];
		if(percentLeft >= 66) colorh = "00FF00";
		else if(percentLeft >= 33) colorh = "ffff00";
		else colorh = "ff0000";
		Format(message, sizeof(message), "►[<font color='" ... COLOR_BOSSNAME ... "'>%s</font>]◄ [%d%%] HP: <font class='fontSize-xl' font color='#%s'>%d</font>\n<font class='%s' color='%s'>", bosses[id].szDisplayName, percentLeft, colorh, totalHP, circleClass, circleColor);
		*/
		Format(message, sizeof(message), "<font class='fontSize-l'> %s \n Életerö: %d | %d%% | \n",bosses[id].szDisplayName, totalHP, percentLeft);
	}


	for (int i = 0; i < bosses[id].iCurrentBars; i++) {
		StrCat(message, sizeof(message), " ✦");
	}
	for (int i = 0; i < bosses[id].iMaxBars - bosses[id].iCurrentBars; i++) {
		StrCat(message, sizeof(message), " ✧");
	}//✧✦
	StrCat(message, sizeof(message), "</font>");

	StrCat(szMessage, len, message);
}

stock void ShowOverlayToClient(int client, const char[] overlaypath) {
	ClientCommand(client, "r_screenoverlay \"%s\"", overlaypath);
}

public void Hitmarker_StartBoss(int client) {
	char buffer[100]; 
	strcopy(buffer, sizeof(buffer), g_sBossHitmarker);
	ReplaceString(buffer, sizeof(buffer), ".vmt", "", false);
	ShowOverlayToClient(client, buffer);

	g_iHitmarkerTime[client] = GetTime() + DELAY_HITMARKER;
}
public void Hitmarker_StartZombie(int client) {
	char buffer[100];
	strcopy(buffer, sizeof(buffer), g_sZombieHitmarker);
	ReplaceString(buffer, sizeof(buffer), ".vmt", "", false);
	ShowOverlayToClient(client, buffer);

	g_iHitmarkerTime[client] = GetTime() + DELAY_HITMARKER;
}
public void Hitmarker_Reset(int client) {
	if(IsValidClient(client))
		ShowOverlayToClient(client, "");
	g_iHitmarkerTime[client] = -1;
}

public Action Command_CHP(int client, int argc) {
	if (!IsValidEntity(simplehud.iEntID[client])) {
		CPrintToChat(client, "%t", "Invalid Entity", simplehud.iEntID[client]);
		return Plugin_Handled;
	}

	char szName[64], szType[64];
	int health;
	GetEntityClassname(simplehud.iEntID[client], szType, sizeof(szType));
	GetEntPropString(simplehud.iEntID[client], Prop_Data, "m_iName", szName, sizeof(szName));

	if (StrEqual(szType, "math_counter", false)) {
		health = GetCounterValue(simplehud.iEntID[client]);
	} else {
		health = GetEntProp(simplehud.iEntID[client], Prop_Data, "m_iHealth");
	}

	CPrintToChat(client, "%t", "Change Entity Hp", szName, simplehud.iEntID[client], szType, health);
	return Plugin_Handled;
}

public Action Command_SHP(int client, int argc) {
	if (!IsValidEntity(simplehud.iEntID[client])) {
		CPrintToChat(client, "%t", "Invalid Entity", simplehud.iEntID[client]);
		return Plugin_Handled;
	}

	if (argc < 1) {
		ReplyToCommand(client, "[SM] Usage: sm_subtracthp <health>");
		return Plugin_Handled;
	}

	char szName[64], szType[64], arg[8];
	int health, max;

	GetEntityClassname(simplehud.iEntID[client], szType, sizeof(szType));
	GetEntPropString(simplehud.iEntID[client], Prop_Data, "m_iName", szName, sizeof(szName));
	GetCmdArg(1, arg, sizeof(arg));
	SetVariantInt(StringToInt(arg));

	if (StrEqual(szType, "math_counter", false)) {
		health = GetCounterValue(simplehud.iEntID[client]);

		if (GetTrieValue(EntityMaxes, szName, max) && max != RoundFloat(GetEntPropFloat(simplehud.iEntID[client], Prop_Data, "m_flMax")))
			AcceptEntityInput(simplehud.iEntID[client], "Add", client, client);
		else
			AcceptEntityInput(simplehud.iEntID[client], "Subtract", client, client);

		CPrintToChat(client, "%t", "Health subtracted", StringToInt(arg), health, health - StringToInt(arg));
	} else {
		health = GetEntProp(simplehud.iEntID[client], Prop_Data, "m_iHealth");
		AcceptEntityInput(simplehud.iEntID[client], "RemoveHealth", client, client);
		CPrintToChat(client, "%t", "Health subtracted", StringToInt(arg), health, health - StringToInt(arg));
	}

	return Plugin_Handled;
}

public Action Command_AHP(int client, int argc) {
	if (!IsValidEntity(simplehud.iEntID[client])) {
		CPrintToChat(client, "%t", "Invalid Entity", simplehud.iEntID[client]);
		return Plugin_Handled;
	}

	if (argc < 1) {
		ReplyToCommand(client, "[SM] Usage: sm_addhp <health>");
		return Plugin_Handled;
	}

	char szName[64], szType[64], arg[8];
	int health, max;

	GetEntityClassname(simplehud.iEntID[client], szType, sizeof(szType));
	GetEntPropString(simplehud.iEntID[client], Prop_Data, "m_iName", szName, sizeof(szName));
	GetCmdArg(1, arg, sizeof(arg));
	SetVariantInt(StringToInt(arg));

	if (StrEqual(szType, "math_counter", false)) {
		health = GetCounterValue(simplehud.iEntID[client]);

		if (GetTrieValue(EntityMaxes, szName, max) && max != RoundFloat(GetEntPropFloat(simplehud.iEntID[client], Prop_Data, "m_flMax")))
			AcceptEntityInput(simplehud.iEntID[client], "Subtract", client, client);
		else
			AcceptEntityInput(simplehud.iEntID[client], "Add", client, client);

		CPrintToChat(client, "%t", "Health added", StringToInt(arg), health, health + StringToInt(arg));
	} else {
		health = GetEntProp(simplehud.iEntID[client], Prop_Data, "m_iHealth");
		AcceptEntityInput(simplehud.iEntID[client], "AddHealth", client, client);
		CPrintToChat(client, "%t", "Health added", StringToInt(arg), health, health + StringToInt(arg));
	}

	return Plugin_Handled;
}