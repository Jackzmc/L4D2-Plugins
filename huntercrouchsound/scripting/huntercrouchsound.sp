#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#define HUNTER       3
#define MAX_HUNTERSOUND         6
#define IS_VALID_CLIENT(%1)     (%1 > 0 && %1 <= MaxClients)
#define IS_INFECTED(%1)         (GetClientTeam(%1) == 3)
#define IS_VALID_INGAME(%1)     (IS_VALID_CLIENT(%1) && IsClientInGame(%1))
#define IS_VALID_INFECTED(%1)   (IS_VALID_INGAME(%1) && IS_INFECTED(%1))
#define DEBUG 0
#define HUNTERCROUCHTRACKING_TIMER 1.8

new const String: sHunterSound[MAX_HUNTERSOUND + 1][] =
{
  "player/hunter/voice/idle/hunter_stalk_01.wav",
	"player/hunter/voice/idle/hunter_stalk_04.wav",
	"player/hunter/voice/idle/hunter_stalk_05.wav",
	"player/hunter/voice/idle/hunter_stalk_06.wav",
	"player/hunter/voice/idle/hunter_stalk_07.wav",
	"player/hunter/voice/idle/hunter_stalk_08.wav",
	"player/hunter/voice/idle/hunter_stalk_09.wav"
};

new bool:isHunter[MAXPLAYERS+1];
static					g_iOffsetFallVelocity					= -1;
static	const	String:	CLASSNAME_TERRORPLAYER[] 				= "CTerrorPlayer";
static	const	String:	NETPROP_FALLVELOCITY[]					= "m_flFallVelocity";
new bool:haspounced[MAXPLAYERS + 1] = {false};
new pouncedvictim[MAXPLAYERS + 1] = {0};

public Plugin:myinfo = 
{
    name = "Hunter Crouch Sounds",
    author = "High Cookie & Harry",
    description = "Forces silent but crouched hunters to emitt sounds",
    version = "1.4",
    url = ""
};

public OnPluginStart()
{
   HookEvent("player_spawn",Event_PlayerSpawn,              EventHookMode_Post);
   HookEvent("player_death", Event_PlayerDeath);
   HookEvent("round_start", event_RoundStart);
   HookEvent("lunge_pounce", PlayerLunge_Pounce_Event);
   HookEvent("pounce_stopped", PlayerLunge_Pounce_Stop_Event);
   g_iOffsetFallVelocity = FindSendPropInfo(CLASSNAME_TERRORPLAYER, NETPROP_FALLVELOCITY);
   if (g_iOffsetFallVelocity <= 0) ThrowError("Unable to find fall velocity offset!");
}

public OnMapStart()
{
    for (new i = 0; i <= MAX_HUNTERSOUND; i++)
    {
        PrefetchSound(sHunterSound[i]);
        PrecacheSound(sHunterSound[i], true);
    }
}

public Action:PlayerLunge_Pounce_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new victim = GetClientOfUserId(GetEventInt(event, "victim"));
	if(IsClientAndInGame(client)&&GetClientTeam(client) == 3 && GetEntProp(client, Prop_Send, "m_zombieClass") == HUNTER)
	{
		haspounced[client] = true;
		pouncedvictim[client] = victim;
	}
}

public Action:PlayerLunge_Pounce_Stop_Event(Handle:event, const String:name[], bool:dontBroadcast)
{
	new victim = GetClientOfUserId(GetEventInt(event, "victim"));
	if(IsClientAndInGame(victim)&&GetClientTeam(victim) == 2)
	{
		for (new i = 1; i <= MaxClients; i++) //clear 
		{
			if(pouncedvictim[i] == victim)
			{
				haspounced[i] = false;
				pouncedvictim[i] = 0;
				break;
			}
		}
	}
}
public Action:event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	new i;
	for(i=0;i<=MAXPLAYERS;++i)
	{
		isHunter[i] = false;
		haspounced[i] = false;
		pouncedvictim[i] = 0;
	}
}

public Action: Event_PlayerSpawn( Handle:event, const String:name[], bool:dontBroadcast )
{
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    if ( !IS_VALID_INFECTED(client) ) { return; }
    
    new zClass = GetEntProp(client, Prop_Send, "m_zombieClass");
    if (zClass == HUNTER)
	{
		haspounced[client] = false;
		isHunter[client] = true;
		CreateTimer(HUNTERCROUCHTRACKING_TIMER, HunterCrouchTracking, client, TIMER_REPEAT);
	}
}

public Action:HunterCrouchTracking(Handle:timer, any:client) 
{
	if (!isHunter[client]) {return Plugin_Stop;}

	if ( !IsClientAndInGame(client) || GetClientTeam(client) != 3 || GetEntProp(client, Prop_Send, "m_zombieClass") != HUNTER || !IsPlayerAlive(client))
	{
		isHunter[client] = false;
		return Plugin_Stop;
	}
	
	if (HasTarget(client))
	{
		return Plugin_Continue;
	}
	
	if (GetClientButtons(client) & IN_DUCK){ return Plugin_Continue; }
	new ducked = GetEntProp(client, Prop_Send, "m_bDucked");
	if (ducked && GetEntDataFloat(client, g_iOffsetFallVelocity) == 0.0)
	{
		#if DEBUG
			PrintToChatAll("0.2s later check again");
		#endif
		CreateTimer(0.2, HunterCrouchReallyCheck, client, _);
	}
	return Plugin_Continue;
}

public Action:HunterCrouchReallyCheck(Handle:timer, any:client) 
{
	if ( !IsClientAndInGame(client) || GetClientTeam(client) != 3 || GetEntProp(client, Prop_Send, "m_zombieClass") != HUNTER || !IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}
	if (GetClientButtons(client) & IN_DUCK){ return Plugin_Continue; }
	new ducked = GetEntProp(client, Prop_Send, "m_bDucked");
	if (ducked && GetEntDataFloat(client, g_iOffsetFallVelocity) == 0.0)
	{
		new rndPick = GetRandomInt(0, MAX_HUNTERSOUND);
		EmitSoundToAll(sHunterSound[rndPick], client, SNDCHAN_VOICE);
		#if DEBUG
			PrintToChatAll("Spawn Sound");
		#endif
	}
	return Plugin_Continue;
}

public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast) 
{
	new victim = GetEventInt(event, "userid");
	new client = GetClientOfUserId(victim);
	isHunter[client] = false;
	haspounced[client] = false;
}

bool:HasTarget(hunter)
{
	return (haspounced[hunter]);
}

stock bool:IsClientAndInGame(index)
{
	return IsClient(index) && IsClientInGame(index);
}

stock bool:IsClient(index)
{
	return index > 0 && index <= MaxClients;
}
