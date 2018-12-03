/**
* L4D Force Mission Changer
* For Sourcemod 1.2.0
* 
* CREDITS:
* 			DDR Khat
* 			Red Alex
*
* Version 1.4.2: 		support l4d2 (sm_l4d_mapchanger.txt)
* Version 1.4.0:		New plugin and config name sm_l4d_mapchanger (old sm_l4dvs_mapchanger.smx will be automatically deleted)
*						Hook change gamemode event and autoload mission list for new gamemode on the server
*						Add support sm_l4dco_mapchanger.txt and sm_l4dvs_mapchanger.txt for coop and versus gamemodes
*						Plugin stop activity if discovered survival gamemode and wait for change gamemode to coop or versus or change map
* Version 1.3.6:		Fix autoloading of a following map bug
*						Fix custom settings for versus map bug
* Version 1.3.5:		Add autoloading of a following map of the list if the server has become empty
* Version 1.3.4:		Any critical bugs fixes (thx Red Alex)
* Version 1.3.3:		Add support of wrong custom versus map
*						Add server commands:
*												sm_l4d_fmc_crec_add - Add custom value sm_l4d_fmc_crec for the specified map. Max 50.
*												Use: sm_l4d_fmc_crec_add <existing custom map> <custom sm_l4d_fmc_crec integer value (max 99)> <custom sm_l4d_fmc_re_timer_block float value>
*												sm_l4d_fmc_crec_clear - Clear all custom value sm_l4d_fmc_crec.
*												sm_l4d_fmc_crec_list - Show all custom value sm_l4d_fmc_crec.
*						Manual set next mission name in sm_l4dvs_mapchanger.txt
*						Add displays and log team winner index at round_end in debug mode
* Version 1.3.2: 		Fix mission announce bug
*						Add cvar sm_l4d_fmc_dbug write event log to file
*						Add cvar sm_l4d_fmc_re_timer_block block double event round_end
* Version 1.3.1:		Ready for L4D version 1.0.1.2
*/

#pragma semicolon 1
#include <sourcemod>
#include <colors>

#define Version "1.4.2"
#define MAX_ARRAY_LINE 50
#define MAX_MAPNAME_LEN 64
#define MAX_CREC_LEN 2
#define MAX_REBFl_LEN 8

new Handle:cvarAnnounce = INVALID_HANDLE;
new Handle:Allowed = INVALID_HANDLE;
//new Handle:AllowedDie = INVALID_HANDLE;
new Handle:DebugEvent = INVALID_HANDLE;
new Handle:DefM;
new Handle:CheckRoundCounter;
new Handle:ChDelayVS;
//new Handle:ChDelayCOOP;
new Handle:TimerRoundEndBlockVS;

new Handle:hKVSettings = INVALID_HANDLE;

//new Handle:CurrentGameMode = INVALID_HANDLE;

new Handle:logfile;

new String:FMC_FileSettings[128];
new String:current_map[64];
new String:announce_map[64];
new String:next_mission_def[64];
new String:next_mission_force[64];
new String:force_mission_name[64];
new RoundEndCounter = 0;
new RoundEndCounterValue = 0;
new RoundEndBlock = 0;
new Float:RoundEndBlockValue = 0.0;

new String:MapNameArrayLine[MAX_ARRAY_LINE][MAX_MAPNAME_LEN];
new String:CrecNumArrayLine[MAX_ARRAY_LINE][MAX_CREC_LEN];
new String:reBlkFlArrayLine[MAX_ARRAY_LINE][MAX_REBFl_LEN];
new g_ArrayCount = 0;

public Plugin:myinfo = 
{
	name = "L4D Force Mission Changer",
	author = "Dionys",
	description = "Force change to next mission when current mission end.",
	version = Version,
	url = "skiner@inbox.ru"
};

public OnPluginStart()
{
	decl String:ModName[50];
	GetGameFolderName(ModName, sizeof(ModName));

	if(!StrEqual(ModName, "left4dead2", false))
		SetFailState("Use this Left 4 Dead 2 only.");

	hKVSettings=CreateKeyValues("ForceMissionChangerSettings");

	HookEvent("round_end", Event_RoundEnd);
	//HookEvent("finale_win", Event_FinalWin);
	//HookEvent("mission_lost", Event_FinalLost);
	
	CreateConVar("sm_l4d_fmc_version", Version, "Version of L4D Force Mission Changer plugin.", FCVAR_NOTIFY);
	DebugEvent = CreateConVar("sm_l4d_fmc_dbug", "0", "on-off Write event to log file.");
	Allowed = CreateConVar("sm_l4d_fmc", "1", "Enables Force changelevel when mission end.");
	//AllowedDie = CreateConVar("sm_l4d_fmc_ifdie", "1", "Enables Force changelevel when all player die on final map in coop gamemode.");
	DefM = CreateConVar("sm_l4d_fmc_def", "l4d_vs_hospital01_apartment", "Mission for change by default.");
	CheckRoundCounter = CreateConVar("sm_l4d_fmc_crec", "4", "Quantity of events RoundEnd before force of changelevel in versus: 4 for l4d <> 1.0.1.2");
	ChDelayVS = CreateConVar("sm_l4d_fmc_chdelayvs", "0.0", "Delay before versus mission change (float in sec).");
	//ChDelayCOOP = CreateConVar("sm_l4d_fmc_chdelaycoop", "0.0", "Delay before coop mission change (float in sec).");
	TimerRoundEndBlockVS = CreateConVar("sm_l4d_fmc_re_timer_block", "0.5", "Time in which current event round_end is not considered (float in sec).");
	cvarAnnounce = CreateConVar("sm_l4d_fmc_announce", "1", "Enables next mission to advertise to players.");
	
	//For custom crec
	RegServerCmd("sm_l4d_fmc_crec_add", Command_CrecAdd, "Add custom value sm_l4d_fmc_crec and sm_l4d_fmc_re_timer_block for the specified map. Max 50.");
	RegServerCmd("sm_l4d_fmc_crec_clear", Command_CrecClear, "Clear all custom value sm_l4d_fmc_crec and sm_l4d_fmc_re_timer_block.");
	RegServerCmd("sm_l4d_fmc_crec_list", Command_CrecList, "Show all custom value sm_l4d_fmc_crec and sm_l4d_fmc_re_timer_block.");
	
	//CurrentGameMode = FindConVar("sm_cvar mp_gamemode");
	//HookConVarChange(CurrentGameMode, OnCVGameModeChange);

	logfile = OpenFile("/addons/sourcemod/logs/fmc_event.log", "w");
}

public OnMapStart()
{
	// Execute the config file
	AutoExecConfig(true, "sm_l4d_mapchanger");
	
	RoundEndCounter = 0;
	RoundEndBlock = 0;

	if (GetConVarInt(DebugEvent) == 1)	
		WriteFileLine(logfile, "***New map start***");

	if(GetConVarInt(Allowed) == 1)
	{
		PluginInitialization();
		
		if (GetConVarInt(DebugEvent) == 1)
		{
			PrintToChatAll("\x04[FMC DEBUG]\x03 MapStart: RECV: \"%d\" REBV: \"%d\"", RoundEndCounterValue, RoundEndBlockValue);
			decl String:mBuffer[128];
			Format(mBuffer, sizeof(mBuffer), "MapStart: RECV: \"%d\" REBV: \"%d\"", RoundEndCounterValue, RoundEndBlockValue);
			WriteFileLine(logfile, mBuffer);
		}
	}
}

public OnMapEnd()
{
	if (GetConVarInt(DebugEvent) == 1)
	{
		PrintToChatAll("\x04[FMC DEBUG]\x03 MapEnd");
		FlushFile(logfile);
		WriteFileLine(logfile, "***Map end***");
	}
}

public OnClientPutInServer(client)
{
	// Make the announcement in 20 seconds unless announcements are turned off
	if(client && !IsFakeClient(client) && GetConVarBool(cvarAnnounce))
		CreateTimer(20.0, TimerAnnounce, client);
}

public OnClientDisconnect(client)
{
	if (GetClientCount(true) <= 0)
	{
		decl String:EmptyServerMap[64];

		if (StrEqual(next_mission_force, "none") == true) EmptyServerMap = next_mission_def;
		else EmptyServerMap = next_mission_force;

		/*if (GetConVarInt(DebugEvent) == 1)
		{
			decl String:mBuffer[128];
			Format(mBuffer, sizeof(mBuffer), "MODE: \"%d\" MAP: \"%s\" EVENT: changemission to \"%s\" REASON: Server is empty", l4d_gamemode(), current_map, EmptyServerMap);
			WriteFileLine(logfile, mBuffer);
		}*/

		ServerCommand("changelevel %s", EmptyServerMap);
	}
}

public Action:Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (RoundEndBlock == 0)
	{
		RoundEndCounter += 1;
		RoundEndBlock = 1;
		CreateTimer(GetConVarFloat(TimerRoundEndBlockVS), TimerRoundEndBlock);
	}

	/*if (GetConVarInt(DebugEvent) == 1)
	{
		new winnerteam = GetEventInt(event, "winner");

		PrintToChatAll("\x04[FMC DEBUG]\x03 MODE: \"%d\" EVENT: \"%s\" NUM: \"%d\" TWIN: \"%d\"", l4d_gamemode(), name, RoundEndCounter, winnerteam);
		decl String:mBuffer[128];
		Format(mBuffer, sizeof(mBuffer), "MODE: \"%d\" MAP: \"%s\" EVENT: \"%s\" NUM: \"%d\" TWIN: \"%d\"", l4d_gamemode(), current_map, name, RoundEndCounter, winnerteam);
		WriteFileLine(logfile, mBuffer);
	}*/
	
	//if(GetConVarInt(Allowed) == 1 && l4d_gamemode() == 2 && StrEqual(next_mission_force, "none") != true && GetConVarInt(CheckRoundCounter) != 0 && RoundEndCounter >= RoundEndCounterValue)
	if(GetConVarInt(Allowed) == 1 && StrEqual(next_mission_force, "none") != true && GetConVarInt(CheckRoundCounter) != 0 && RoundEndCounter >= RoundEndCounterValue)
	{
		/*if (GetConVarInt(DebugEvent) == 1)
		{
			PrintToChatAll("\x04[FMC DEBUG]\x03 MODE: \"%d\" EVENT: START FMC TIMER ", l4d_gamemode());
			decl String:mBuffer[128];
			Format(mBuffer, sizeof(mBuffer), "MODE: \"%d\" MAP: \"%s\" EVENT: START FMC TIMER ", l4d_gamemode(), current_map);
			WriteFileLine(logfile, mBuffer);
		}*/

		CreateTimer(RoundEndBlockValue, TimerChDelayVS);
		RoundEndCounter = 0;
	}
}

/*
public Action:Event_FinalWin(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (GetConVarInt(DebugEvent) == 1)
	{
		PrintToChatAll("\x04[FMC DEBUG]\x03 MODE: \"%d\" EVENT: \"%s\" ", l4d_gamemode(), name);
		decl String:mBuffer[128];
		Format(mBuffer, sizeof(mBuffer), "MODE: \"%d\" MAP: \"%s\" EVENT: \"%s\" ", l4d_gamemode(), current_map, name);
		WriteFileLine(logfile, mBuffer);
	}

	if(GetConVarInt(Allowed) == 1 && l4d_gamemode() == 1 && StrEqual(next_mission_force, "none") != true)
		CreateTimer(GetConVarFloat(ChDelayCOOP), TimerChDelayCOOP);
}*/
/*
public Action:Event_FinalLost(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (GetConVarInt(DebugEvent) == 1)
	{
		PrintToChatAll("\x04[FMC DEBUG]\x03 MODE: \"%d\" EVENT: \"%s\" ", l4d_gamemode(), name);
		decl String:mBuffer[128];
		Format(mBuffer, sizeof(mBuffer), "MODE: \"%d\" MAP: \"%s\" EVENT: \"%s\" ", l4d_gamemode(), current_map, name);
		WriteFileLine(logfile, mBuffer);
	}

	if(GetConVarInt(Allowed) == 1 && GetConVarInt(AllowedDie) && l4d_gamemode() == 1 && StrEqual(next_mission_force, "none") != true)
		CreateTimer(GetConVarFloat(ChDelayCOOP), TimerChDelayCOOP);
}*/
/*
public OnCVGameModeChange(Handle:convar, const String:oldValue[], const String:newValue[])
{
	//If game mode actually changed
	if (strcmp(oldValue, newValue) != 0)
	{
		new GameMode = l4d_gamemode();
		if (GameMode == 1 || GameMode == 2 || GameMode == 3)
		{
			HookEvent("round_end", Event_RoundEnd);
			//HookEvent("finale_win", Event_FinalWin);
			//HookEvent("mission_lost", Event_FinalLost);
		}

		if(GetConVarInt(Allowed) == 1)
			PluginInitialization();
	}
}*/

public Action:TimerAnnounce(Handle:timer, any:client)
{
	if(IsClientInGame(client))
	{
		if (StrEqual(next_mission_force, "none") != true)
		{
			CPrintToChat(client, "{default}[{olive}JS{default}]本地圖最終張{default}，{red}若沒要打下一場請跟隊友說{default}，{red}要懂禮貌{default}!");
			CPrintToChat(client, "{default}[{olive}JS{default}]{default} 下一張圖{default}: {blue}%s{default}.", announce_map);
		}
		//else
		//	CPrintToChat(client, "{default}[{olive}JS{default}]{default} 本{green}SV{default}管理員:{blue}JJ{default}、{blue}哈利{default}、{blue}stone{default}、{blue}老爹{default}.");
	}
}

public Action:TimerRoundEndBlock(Handle:timer)
{
	RoundEndBlock = 0;
}

public Action:TimerChDelayVS(Handle:timer)
{
	/*if (GetConVarInt(DebugEvent) == 1)
	{
		PrintToChatAll("\x04[FMC DEBUG]\x03 MODE: \"%d\" EVENT: changemission to \"%s\" ", l4d_gamemode(), next_mission_force);
		decl String:mBuffer[128];
		Format(mBuffer, sizeof(mBuffer), "MODE: \"%d\" MAP: \"%s\" EVENT: changemission to \"%s\" ", l4d_gamemode(), current_map, next_mission_force);
		WriteFileLine(logfile, mBuffer);
	}*/

	ServerCommand("changelevel %s", next_mission_force);
}
/*
public Action:TimerChDelayCOOP(Handle:timer)
{
	ServerCommand("changelevel %s", next_mission_force);
}*/

public Action:Command_CrecClear(args)
{
	g_ArrayCount = 0;
	PrintToServer("[FMC] Custom value sm_l4d_fmc_crec now is clear.");
}

public Action:Command_CrecAdd(args)
{
	if (g_ArrayCount == MAX_ARRAY_LINE)
	{
		PrintToServer("[FMC] Max number of array line for sm_l4d_fmc_crec_add reached.");
		return;
	}

	decl String:cmdarg1[MAX_MAPNAME_LEN];
	GetCmdArg(1, cmdarg1, sizeof(cmdarg1));
	decl String:cmdarg2[MAX_CREC_LEN];
	GetCmdArg(2, cmdarg2, sizeof(cmdarg2));
	decl String:cmdarg3[MAX_REBFl_LEN];
	GetCmdArg(3, cmdarg3, sizeof(cmdarg3));

	// Check for doubles
	new bool:isDouble = false;
	for (new i = 0; i < g_ArrayCount; i++)
	{
		if (StrEqual(cmdarg1, MapNameArrayLine[i]) == true)
		{
			isDouble = true;
			break;
		}
	}

	if (IsMapValid(cmdarg1) && StringToInt(cmdarg2) != 0 && StringToFloat(cmdarg3) != 0.0)
	{
		if (!isDouble)
		{
			strcopy(MapNameArrayLine[g_ArrayCount], MAX_MAPNAME_LEN, cmdarg1);
			strcopy(CrecNumArrayLine[g_ArrayCount], MAX_CREC_LEN, cmdarg2);
			strcopy(reBlkFlArrayLine[g_ArrayCount], MAX_REBFl_LEN, cmdarg3);
			g_ArrayCount++;
		}
	}
	else
		PrintToServer("[FMC] Error command. Use: sm_l4d_fmc_crec_add <existing custom map> <custom sm_l4d_fmc_crec integer value (max 99)> <custom sm_l4d_fmc_re_timer_block float value>.");
}

public Action:Command_CrecList(args)
{
	PrintToServer("[FMC] Custom value sm_l4d_fmc_crec and sm_l4d_fmc_re_timer_block list:");
	for (new i = 0; i < g_ArrayCount; i++)
	{
		PrintToServer("[%d] %s - %s - %s", i, MapNameArrayLine[i], CrecNumArrayLine[i], reBlkFlArrayLine[i]);
	}
	PrintToServer("[FMC] Custom value sm_l4d_fmc_crec and sm_l4d_fmc_re_timer_block list end.");
}
/*
l4d_gamemode()
{
	// 1 - coop / 2 - versus / 3 - survival / or false (thx DDR Khat for code)
	new String:gmode[32];
	GetConVarString(FindConVar("sm_cvar mp_gamemode"), gmode, sizeof(gmode));

	if (strcmp(gmode, "coop") == 0)
	{
		return 1;
	}
	else if (strcmp(gmode, "versus", false) == 0)
	{
		return 2;
	}
	else if (strcmp(gmode, "survival", false) == 0)
	{
		return 3;
	}
	else
	{
		return false;
	}
}
*/
ClearKV(Handle:kvhandle)
{
	KvRewind(kvhandle);
	if (KvGotoFirstSubKey(kvhandle))
	{
		do
		{
			KvDeleteThis(kvhandle);
			KvRewind(kvhandle);
		}
		while (KvGotoFirstSubKey(kvhandle));
		KvRewind(kvhandle);
	}
}

PluginInitialization()
{

	ClearKV(hKVSettings);
	
	BuildPath(Path_SM, FMC_FileSettings, 128, "data/sm_l4d_mapchanger.txt");
	PrintToServer("[FMC] Discovered versus gamemode. Link to sm_l4d_mapchanger.");
	
	if(!FileToKeyValues(hKVSettings, FMC_FileSettings))
		SetFailState("Force Mission Changer settings not found! Shutdown.");
	
	next_mission_force = "none";
	GetCurrentMap(current_map, 64);
	LogMessage("current map: %s",current_map);
	GetConVarString(DefM, next_mission_def, 64);

	KvRewind(hKVSettings);
	if(KvJumpToKey(hKVSettings, current_map))
	{
		KvGetString(hKVSettings, "next mission map", next_mission_force, 64, next_mission_def);
		LogMessage("next_mission map: %s",next_mission_force);
		KvGetString(hKVSettings, "next mission name", force_mission_name, 64, "none");
		LogMessage("next mission name: %s",force_mission_name);
	}
	KvRewind(hKVSettings);
		
	if (StrEqual(next_mission_force, "none") != true)
	{
		if (!IsMapValid(next_mission_force))
			next_mission_force = next_mission_def;

		if (StrEqual(force_mission_name, "none") != true)
			announce_map = force_mission_name;
		else
			announce_map = next_mission_force;
				
		RoundEndCounterValue = 0;
		RoundEndBlockValue = 0.0;
		for (new i = 0; i < g_ArrayCount; i++)
		{
			if (StrEqual(current_map, MapNameArrayLine[i]) == true)
			{
				RoundEndCounterValue = StringToInt(CrecNumArrayLine[g_ArrayCount]);
				RoundEndBlockValue = StringToFloat(reBlkFlArrayLine[g_ArrayCount]);
				break;
			}
		}
		if (RoundEndCounterValue == 0)
			RoundEndCounterValue = GetConVarInt(CheckRoundCounter);
		if (RoundEndBlockValue == 0.0)
			RoundEndBlockValue = GetConVarFloat(ChDelayVS);
	}
}
