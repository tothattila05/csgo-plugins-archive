#include <lvl_ranks>
#include <cstrike>
#include <sourcemod>
#include <clientprefs>

public Plugin myinfo =
{
	name = "LifeLine - Játékosinformáció",
	author = "Tóth Attila",
	version = "1.0.0",
	url = ""
};

Handle g_hCookie;
char g_sRanksInfo[128][192];
bool g_bUse[MAXPLAYERS +1];

#define SZF(%0) %0, sizeof(%0)
#define CyclePlayers(%0) for(int %0 = 1; %0 <= MaxClients; ++%0) if(IsClientInGame(%0))
public void OnPluginStart()
{
	LoadTranslations("lr_core_ranks.phrases");
	LoadTranslations("lr_module_players_info.phrases.txt");

	char sPath[64];
	BuildPath(Path_SM, SZF(sPath), "configs/levels_ranks/settings_ranks.ini");
	KeyValues hKeyValues = new KeyValues("LR_Settings");
	if(!hKeyValues.ImportFromFile(sPath))
		SetFailState("No found file: '%s'", sPath);

	hKeyValues.Rewind();
	if(!hKeyValues.JumpToKey("Ranks"))
		SetFailState("No found key: 'Ranks'", sPath);

	int iCount;
	hKeyValues.GotoFirstSubKey();
	do hKeyValues.GetSectionName(g_sRanksInfo[iCount++], sizeof(g_sRanksInfo[]));
	while(hKeyValues.GotoNextKey());
	delete hKeyValues;

	CreateTimer(1.0, view_as<Timer>(TimerUpdate), _, TIMER_REPEAT);

	g_hCookie = RegClientCookie("levelranks_playerinfo", "On/off player information", CookieAccess_Private);

	CreateTimer(0.1, Timer_PrintMessageFiveTimes, _, TIMER_REPEAT);
	
	CyclePlayers(iClient)
		OnClientCookiesCached(iClient);

	if(LR_IsLoaded())
		LR_OnCoreIsReady();
		
	//HookEvent("player_say", Event_PlayerSay, EventHookMode_Pre)
}

public Action Timer_PrintMessageFiveTimes(Handle timer)
{
	char sRank[64];
	int iRank;
	
	for(new i=1;i<=MaxClients;i++)
	{
    	if(IsClientInGame(i) && IsPlayerAlive(i))
    	{
    		if((iRank = LR_GetClientInfo(i, ST_RANK) -1) == -1)
				iRank = 0;
				
			char authid[64];
			GetClientAuthId(i, AuthId_Steam2, authid, sizeof(authid)); 
				
			SetGlobalTransTarget(i);
			FormatEx(SZF(sRank), "%t", g_sRanksInfo[iRank], i);
			
			if(StrContains(sRank, "Silver I", true) != -1 || StrContains(sRank, "Silver II", true) != -1 || StrContains(sRank, "Silver III", true) != -1 || StrContains(sRank, "Silver IV", true) != -1 || StrContains(sRank, "Silver Elite", true) != -1 || StrContains( sRank, "Silver Elite Master", true) != -1 && !StrEqual(authid, "STEAM_1:0:168023262"))
				 CS_SetClientClanTag(i, "[KEZDŐ]");
			
            if(StrContains( sRank, "Gold Nova I", true) != -1 || StrContains( sRank, "Gold Nova II", true) != -1 || StrContains( sRank, "Gold Nova III", true) != -1 || StrContains( sRank, "Gold Nova Master", true) != -1 && !StrEqual(authid, "STEAM_1:0:168023262"))
                CS_SetClientClanTag(i, "[HALADÓ]");

            if(StrContains( sRank, "Master Guardian I", true) != -1 || StrContains( sRank, "Master Guardian II", true) != -1 || StrContains( sRank, "Master Guardian Elite", true) != -1 && !StrEqual(authid, "STEAM_1:0:168023262"))
                CS_SetClientClanTag(i, "[PROFI]");
                      
            if(StrContains( sRank, "Distinguished Master Guardian", true) != -1 || StrContains( sRank, "Legendary Eagle", true) != -1 || StrContains( sRank, "Legendary Eagle Master", true) != -1 && !StrEqual(authid, "STEAM_1:0:168023262"))
                CS_SetClientClanTag(i, "[MESTER]");
                
            if(StrContains( sRank, "Supreme Master First Class", true) != -1 || StrContains( sRank, "The Global Elite", true) != -1 && !StrContains(authid, "STEAM_1:0:168023262"))
                CS_SetClientClanTag(i, "[VETERÁN]");
		
			if (CheckCommandAccess(i, "", ADMFLAG_ROOT, true) && !StrEqual(authid, "STEAM_1:0:168023262"))
				CS_SetClientClanTag(i, "[TULAJDONOS]");
			
			if (CheckCommandAccess(i, "", ADMFLAG_GENERIC, true) && !CheckCommandAccess(i, "", ADMFLAG_ROOT, true) && !StrEqual(authid, "STEAM_1:0:168023262"))
				CS_SetClientClanTag(i, "[ADMIN]");	
			
			if(CheckCommandAccess(i, "", ADMFLAG_KICK, true) && !CheckCommandAccess(i, "", ADMFLAG_ROOT, true) && !CheckCommandAccess(i, "", ADMFLAG_GENERIC, true) && !StrEqual(authid, "STEAM_1:0:168023262"))
				CS_SetClientClanTag(i, "[MODERATOR]");	
			
			if (CheckCommandAccess(i, "", ADMFLAG_CUSTOM1, true) && !CheckCommandAccess(i, "", ADMFLAG_GENERIC, true) && !CheckCommandAccess(i, "", ADMFLAG_ROOT, true) && !CheckCommandAccess(i, "", ADMFLAG_KICK, true) && !StrEqual(authid, "STEAM_1:0:168023262"))
				CS_SetClientClanTag(i, "[VIP]");	
	
    	}
	}
}

public void LR_OnCoreIsReady()
{
	LR_MenuHook(LR_SettingMenu, LR_OnMenuCreated, LR_OnMenuItemSelected);
}

public void LR_OnMenuCreated(LR_MenuType OnMenuType, int iClient, Menu hMenu)
{
	char sBuffer[64];
	FormatEx(SZF(sBuffer), "%T", g_bUse[iClient] ? "Item, on":"Item, off", iClient);
	hMenu.AddItem("playersinfo", sBuffer);
}

void LR_OnMenuItemSelected(LR_MenuType OnMenuType, int iClient, const char[] sInfo)
{
	if(!StrEqual(sInfo, "playersinfo"))
		return;

	PrintToChat(iClient, "%t", (g_bUse[iClient] = !g_bUse[iClient]) ? "Message, on":"Message, off");
	LR_ShowMenu(iClient, LR_SettingMenu);
}

// Show info
#define KD(%0) float(%0 == 0 ? 1 : %0)
void TimerUpdate()
{
	char sRank[64];
	char sBuffer[1024];

	int iRank, iTarget, iKills, iDeaths, iAssists, iSeconds;
	CyclePlayers(iClient)
	{
		if(g_bUse[iClient] && !IsFakeClient(iClient) && !IsPlayerAlive(iClient) && 3 < GetEntProp(iClient, Prop_Send, "m_iObserverMode") < 6 &&
		1 < (iTarget = GetEntPropEnt(iClient, Prop_Send, "m_hObserverTarget")) <= MaxClients && IsClientInGame(iTarget))
		{
			if((iRank = LR_GetClientInfo(iTarget, ST_RANK) -1) == -1)
				iRank = 0;

			SetGlobalTransTarget(iClient);
			FormatEx(SZF(sRank), "%t", g_sRanksInfo[iRank], iClient);

			iKills = LR_GetClientInfo(iTarget, ST_KILLS);
			iDeaths = LR_GetClientInfo(iTarget, ST_DEATHS);
			iAssists = LR_GetClientInfo(iTarget, ST_ASSISTS);
			iSeconds = LR_GetClientInfo(iTarget, ST_PLAYTIME);

			FormatEx(SZF(sBuffer), "%t", "Player information",	sRank,
																LR_GetClientInfo(iTarget, ST_PLACEINTOP),
																LR_GetClientInfo(iTarget, ST_EXP),
																iKills,
																iDeaths,
																iAssists,
																(KD(iKills) + float(iAssists / 2)) / KD(iDeaths),
																LR_GetClientInfo(iTarget, ST_SHOOTS),
																LR_GetClientInfo(iTarget, ST_HITS),
																LR_GetClientInfo(iTarget, ST_HEADSHOTS),
																iSeconds / 3600,
																iSeconds / 60 %60,
																iSeconds %60,
																LR_GetClientInfo(iTarget, ST_PLACEINTOPTIME));

			Protobuf hPb = view_as<Protobuf>(StartMessageOne("HintText", iClient));
			hPb.SetString("text", sBuffer);
			EndMessage();
		}
	}
}

// Get info from cookie and record in variable
public void OnClientCookiesCached(int iClient)
{ 
	if(IsFakeClient(iClient))
		return;

	char sValue[4];
	GetClientCookie(iClient, g_hCookie, SZF(sValue));
	g_bUse[iClient] = sValue[0] ? view_as<bool>(StringToInt(sValue)):true;
}

public void OnClientDisconnect(int iClient)
{
	if(!IsFakeClient(iClient))
		SetClientCookie(iClient, g_hCookie, g_bUse[iClient] ? "1":"0");
}

public void OnPluginEnd()
{
	CyclePlayers(iClient)
		OnClientDisconnect(iClient);
}