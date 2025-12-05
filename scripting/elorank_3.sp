#pragma semicolon 1

#include <sourcemod>
#include <cstrike>
#include <sdkhooks>
#include <sdktools>

new bool:g_bIsRank[MAXPLAYERS+1];
new rank[MAXPLAYERS+1];

public Plugin:myinfo = {
	name = "Competitive Rank",
	author = "Laam4",
	description = "Show your competitive rank on scoreboard",
	version = "1.2",
	url = ""
};

public OnPluginStart() {
	RegConsoleCmd("sm_elorank", Command_SetElo);
	RegConsoleCmd("sm_mm", Command_EloMenu);
}

public OnMapStart() {
	new iIndex = FindEntityByClassname(MaxClients+1, "cs_player_manager");
	if (iIndex == -1) {
		SetFailState("Unable to find cs_player_manager entity");
	}
	
	SDKHook(iIndex, SDKHook_ThinkPost, Hook_OnThinkPost);
}

public OnClientAuthorized(client, const String:auth[])
{
	g_bIsRank[client] = false;	
	new String:error[255];
	new Handle:db = SQL_DefConnect(error, sizeof(error));
	
	if (db == INVALID_HANDLE)
	{
		PrintToServer("Could not connect: %s", error);
	} else {
		if(!IsFakeClient(client)) {
			new String:get_rank[255];
			new Handle:query;
			decl String:buffer[3][32];
			ExplodeString(auth, ":", buffer, 3, 32);
			//PrintToServer("uniqueid: %s:%s", buffer[1], buffer[2]);
			Format(get_rank, sizeof(get_rank), "SELECT hlstats_Players.mmrank FROM hlstats_PlayerUniqueIds LEFT JOIN hlstats_Players ON hlstats_Players.playerId = hlstats_PlayerUniqueIds.playerId WHERE uniqueId = '%s:%s'", buffer[1], buffer[2]);
			query = SQL_Query(db, get_rank);
			if(query == INVALID_HANDLE) {
				SQL_GetError(db, error, sizeof(error));
				PrintToServer("Failed to query (error: %s)", error);
			} else if(SQL_FetchRow(query)) {
				rank[client] = SQL_FetchInt(query, 0);
				//PrintToServer("rank: %d", rank[client]);
				CloseHandle(query);
				if (rank[client] > 0) {
					g_bIsRank[client] = true;
				}
			}
		}
		CloseHandle(db);
	}
}

public OnClientDisconnect(client) {
	g_bIsRank[client] = false;
	rank[client] = 0;
}

public Action:Command_EloMenu(client, args)
{
	if ( IsClientInGame(client) )
	{
		new Handle:MenuHandle = CreateMenu(EloHandler);
		SetMenuTitle(MenuHandle, "Your competitive rank?");
		AddMenuItem(MenuHandle, "0", "No Rank");
		AddMenuItem(MenuHandle, "1", "Silver I");
		AddMenuItem(MenuHandle, "2", "Silver II");
		AddMenuItem(MenuHandle, "3", "Silver III");
		AddMenuItem(MenuHandle, "4", "Silver IV");
		AddMenuItem(MenuHandle, "5", "Silver Elite");
		AddMenuItem(MenuHandle, "6", "Silver Elite Master");
		AddMenuItem(MenuHandle, "7", "Gold Nova I");
		AddMenuItem(MenuHandle, "8", "Gold Nova II");
		AddMenuItem(MenuHandle, "9", "Gold Nova III");
		AddMenuItem(MenuHandle, "10", "Gold Nova Master");
		AddMenuItem(MenuHandle, "11", "Master Guardian I");
		AddMenuItem(MenuHandle, "12", "Master Guardian II");
		AddMenuItem(MenuHandle, "13", "Master Guardian Elite");
		AddMenuItem(MenuHandle, "14", "Distinguished Master Guardian");
		AddMenuItem(MenuHandle, "15", "Legendary Eagle");
		AddMenuItem(MenuHandle, "16", "Legandary Eagle Master");
		AddMenuItem(MenuHandle, "17", "Supreme Master First Class");
		AddMenuItem(MenuHandle, "18", "The Global Elite");

		SetMenuPagination(MenuHandle, 8);
		DisplayMenu(MenuHandle, client, 30);
	}
	return Plugin_Handled;
}

public EloHandler(Handle:menu, MenuAction:action, client, itemNum)
{
	switch(action)
	{
	case MenuAction_Select:
		{
			new String:error[255];
			new Handle:db = SQL_DefConnect(error, sizeof(error));
			new String:info[4];
			GetMenuItem(menu, itemNum, info, sizeof(info));
			rank[client] = StringToInt(info);
			new String:set_rank[255];
			decl String:buffer[3][32];
			new String:auth[64];
			GetClientAuthString(client, auth, sizeof(auth));
			ExplodeString(auth, ":", buffer, 3, 32);
			//PrintToServer("uniqueid: %s:%s", buffer[1], buffer[2]);
			Format(set_rank, sizeof(set_rank), "UPDATE hlstats_PlayerUniqueIds LEFT JOIN hlstats_Players ON hlstats_Players.playerId = hlstats_PlayerUniqueIds.playerId SET hlstats_Players.mmrank='%d' WHERE uniqueId='%s:%s'", rank[client], buffer[1], buffer[2]);
			if (!SQL_FastQuery(db, set_rank))
			{
				SQL_GetError(db, error, sizeof(error));
				PrintToServer("Failed to query (error: %s)", error);
			}
			g_bIsRank[client] = true;
			new String:text[64];
			Format(text, sizeof(text), "Your rank is now ");
			switch(rank[client])
			{
			case 0:PrintToChat(client, "%s\x08No Rank", text);
			case 1:PrintToChat(client, "%s\x0ASilver I", text);
			case 2:PrintToChat(client, "%s\x0ASilver II", text);
			case 3:PrintToChat(client, "%s\x0ASilver III", text);
			case 4:PrintToChat(client, "%s\x0ASilver IV", text);
			case 5:PrintToChat(client, "%s\x0ASilver Elite", text);
			case 6:PrintToChat(client, "%s\x0ASilver Elite Master", text);
			case 7:PrintToChat(client, "%s\x0BGold Nova I", text);
			case 8:PrintToChat(client, "%s\x0BGold Nova II", text);
			case 9:PrintToChat(client, "%s\x0BGold Nova III", text);
			case 10:PrintToChat(client, "%s\x0BGold Nova Master", text);
			case 11:PrintToChat(client, "%s\x0CMaster Guardian I", text);
			case 12:PrintToChat(client, "%s\x0CMaster Guardian II", text);
			case 13:PrintToChat(client, "%s\x0CMaster Guardian Elite", text);
			case 14:PrintToChat(client, "%s\x0CDistinguished Master Guardian", text);
			case 15:PrintToChat(client, "%s\x0ELegendary Eagle", text);
			case 16:PrintToChat(client, "%s\x0ELegandary Eagle Master", text);
			case 17:PrintToChat(client, "%s\x0ESupreme Master First Class", text);
			case 18:PrintToChat(client, "%s\x0FThe Global Elite", text);
			default: PrintToChat(client, "Dunno lol");
			}
		}
	case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

public Action:Command_SetElo(client, args) {
	decl String:arg[64];
	GetCmdArg( 1, arg, 64 ); 
	rank[client] = StringToInt(arg);
	g_bIsRank[client] = true;
	return Plugin_Handled;
}

public Hook_OnThinkPost(iEnt) {
	static iRankOffset = -1;
	if (iRankOffset == -1) {
		iRankOffset = FindSendPropInfo("CCSPlayerResource", "m_iCompetitiveRanking");
	}
	new iRank[65];
	GetEntDataArray(iEnt, iRankOffset, iRank, MaxClients+1);
	for (new i = 1; i <= MaxClients; i++) {
		if (g_bIsRank[i]) {
			iRank[i] = rank[i];
			SetEntDataArray(iEnt, iRankOffset, iRank, MaxClients+1);
		}
	}
}  