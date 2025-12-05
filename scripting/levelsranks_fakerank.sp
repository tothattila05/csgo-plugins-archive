#pragma semicolon 1
#pragma newdecls required

#include <sdkhooks>
#include <sdktools>
#include <lvl_ranks>

#define PLUGIN_NAME "[LR] Module - FakeRank"
#define PLUGIN_AUTHOR "RoadSide Romeo & Wend4r & Fix by MrQout"

int			g_iType,
			m_iCompetitiveRanking;


KeyValues	g_hKv;

public Plugin myinfo = {name = PLUGIN_NAME, author = PLUGIN_AUTHOR, version = PLUGIN_VERSION};
public void OnPluginStart()
{
	if(GetEngineVersion() != Engine_CSGO) SetFailState(PLUGIN_NAME ... " : Plug-in works only on CS:GO");

	m_iCompetitiveRanking = FindSendPropInfo("CCSPlayerResource", "m_iCompetitiveRanking");
	ConfigLoad();
	
	if(LR_IsLoaded())LR_OnCoreIsReady();
}

public void LR_OnCoreIsReady()
{
	LR_Hook(LR_OnSettingsModuleUpdate, ConfigLoad);
}

void ConfigLoad()
{
	static char sPath[PLATFORM_MAX_PATH];
	if(g_hKv) delete g_hKv;
	else BuildPath(Path_SM, sPath, sizeof(sPath), "configs/levels_ranks/fakerank.ini");

	g_hKv = new KeyValues("LR_FakeRank");
	if(!g_hKv.ImportFromFile(sPath))
		SetFailState(PLUGIN_NAME ... " : File is not found (%s)", sPath);

	switch(g_hKv.GetNum("Type", 0))
	{
		case 0: g_iType = 0;
		case 1: g_iType = 50;
		case 2: g_iType = 70;
	}

	g_hKv.GotoFirstSubKey();
	g_hKv.Rewind();
	g_hKv.JumpToKey("FakeRank");
}

public void OnMapStart()
{
	static char sBuffer[256], sRank[12];

	for(int i = LR_GetRankNames().Length + 1, iIndex; i != 1;)
	{
		IntToString(--i, sRank, 12);
		if((iIndex = g_hKv.GetNum(sRank) + g_iType) > 18)
		{
			FormatEx(sBuffer, sizeof(sBuffer), "materials/panorama/images/icons/skillgroups/skillgroup%i.svg", iIndex);
			AddFileToDownloadsTable(sBuffer);
		}
	}
	
	SDKHook(GetPlayerResourceEntity(), SDKHook_ThinkPost, OnThinkPost);
}

void OnThinkPost(int iEnt)
{
	static char sRank[12];
	for(int i = MaxClients + 1; --i;)
	{
		if(LR_GetClientStatus(i))
		{
			IntToString(LR_GetClientInfo(i, ST_RANK), sRank, 12);
			int offset = m_iCompetitiveRanking + i * 4;
			
			
			if (!view_as<bool>(GetEntData(iEnt, offset)))
				SetEntData(iEnt, offset, g_hKv.GetNum(sRank) + g_iType);
		}
	}
}

public void OnPlayerRunCmdPost(int iClient, int iButtons)
{
	static int iOldButtons[MAXPLAYERS+1];
	if(iButtons & IN_SCORE && !(iOldButtons[iClient] & IN_SCORE))
	{
		StartMessageOne("ServerRankRevealAll", iClient, USERMSG_BLOCKHOOKS);
		EndMessage();
	}

	iOldButtons[iClient] = iButtons;
}