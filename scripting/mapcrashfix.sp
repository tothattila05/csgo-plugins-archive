#include <sourcemod>
#include <sdktools>

#pragma semicolon 1
#pragma tabsize 0
#pragma newdecls required

public Plugin myinfo =
{
    name        = "MapCrashFixAll",
    author      = "Kashinoda",
    description = "Prevents client crashes on map change",
    version    = "1.0 Test",
    url        = "https://www.alliedmods.com"
};

public void OnPluginStart()
{
        HookEvent("server_spawn", EventNewMap);
}
 
public void EventNewMap(Event event, const char[] name, bool dontBroadcast)
{

        CreateTimer(2.0, Timer_RetryPlayers);       
        LogMessage("Map change, reconnecting players in 2 seconds...");
}

public Action Timer_RetryPlayers( Handle timer , int _any )
{
        RetryClients(_any);
        return Plugin_Stop;
}

stock bool RetryClients(int forceChange)
{

        for( int i = 1; i <= MaxClients; i++ )
{
        if( IsClientConnected( i ) )
                        {
        ClientCommand( i, "retry" );
        LogMessage("Sending retry to %N", i);
       
                        }
}
        if (!forceChange)
                return;
}