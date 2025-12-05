#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

public void OnPluginStart() 
{ 
    HookEvent("weapon_fire", Event_WeaponFire); 
} 

public void Event_WeaponFire(Event event, const char[] sEventName, bool bDontBroadcast) 
{
	int client = GetClientOfUserId(event.GetInt("userid"));
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
   	
   	static char Weapon[32];
    GetEventString(event, "weapon", Weapon, sizeof(Weapon));
    
    if(StrEqual(Weapon, "deagle"))
    {
       	float gameTime = GetGameTime();
		SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", 5.0 + gameTime);
    }
} 