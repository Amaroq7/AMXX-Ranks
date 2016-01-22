/*
 * AMX Mod X plugin
 *
 * Custom Ranks, v2.2-dev
 *
 * (c) Copyright 2014-2015 - Ni3znajomy
 * This file is provided as is (no warranties).
 *
 */

/*
 * Description:
 *   Simple plugin that adds ranks on your server.
 *
 *
 * Cvar(s):
 *   ranks_show_dead <0|1> - disables/enables showing a player rank for dead players
 *   ranks_diffrence <0|1> - disables/enables setting a rank for player by subtracting his frags with his deaths
 *
 * Requirement:
 *   AMX Mod X 1.8.3 or higher
 *
 *
 * Setup:
 *   Extract the content of this .zip archive on your computer, then upload the "addons" folder
 *   in your moddir (folder of your game).
 *   Add the plugin name in your "plugins.ini" file (or in another plugins file).
 *
 *
 * Configuration:
 *   Put the cvar(s) in your "amxx.cfg" file and configure them yourself as you want.
 *   You can enable the AMXX logs by uncommenting the #define USE_LOGS.
 *   You can change the name of the log file by editing the "new const g_szLogFile[]..." part.
 *
 *
 * Credit(s):
 *   ------
 *
 *
 * Changelog:
 *   2.2-dev o updated to the lastest version of amxx & many improvements
 *   2.1.1  o corrected motd code
 *   2.1.0  o more optimised plugin & ML support & much more configurable
 *   2.0.2  o corrected plugin code
 *   2.0.1  o fixed some bugs and improved motd code
 *   2.0.0  o added automated motd and loading ranks from file
 *   1.0.0  o initial release
 *
 */

/******************************************************************************/
// If you change one of the following settings, do not forget to recompile
// the plugin and to install the new .amx file on your server.
// You can find the list of admin flags in the amxmodx/scripting/include/amxconst.inc file.

//Defines font color in the motd, you can also use hexadecimal colors
#define FONT_COLOR "yellow"

//Defines background color of the motd, you can also use hexadecimal colors
#define BG_COLOR "black"

//Defines a size of font in the motd
#define FONT_SIZE 4

//Admin flag for "ranks_reload" command
#define ADMIN_FLAG ADMIN_CFG

//Defines directory of the configuration file
#define FILE "ranks.ini"

// Uncomment the following line to enable the AMX logs for this plugin.
#define USE_LOGS

// File name where the logs are stored (will be put in the "amxxmodx/logs" directory).
#if defined USE_LOGS
  new const g_szLogFile[] = "ranks.log"
#endif

// Defines hard limit how many ranks can be read from the "ranks.ini" file.
#define MAX_RANKS 25

// Defines how long can be rank name.
#define MAX_NAME_RANK 33

/******************************************************************************/

#include <amxmodx>
#include <amxmisc>
#include <csx>
#include <hamsandwich>
#include <engine>

#define PLUGIN "Custom Ranks"
#define VERSION "2.2-dev"
#define AUTHOR "Ni3znajomy"

new g_pCvarRank, g_pCvarDiff;
new g_iCvarRank, g_iCvarDiff;

#define TASK 3929

new g_iKills[MAX_PLAYERS+1];
new g_szMotd[1012];

new g_szRanks[MAX_RANKS][MAX_NAME_RANK];
new g_iRanks[MAX_RANKS];
new g_szPlayerRank[MAX_PLAYERS+1][MAX_NAME_RANK];
new g_iPlayerLevel[MAX_PLAYERS+1];

new g_iLoaded;

new ShowStats;

#define NoShowSet(%1) (ShowStats |= (1<<(%1-1)))
#define NoShowCheck(%1) (ShowStats & (1<<(%1-1)))
#define NoShowRemove(%1) (ShowStats &= ~(1<<(%1-1)))

#define MaxLevel (g_iLoaded - 1)

new g_hHud;

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)
		    
	create_cvar("ranks_version", VERSION, FCVAR_SPONLY|FCVAR_SERVER);
	
	register_clcmd("say /ranks", "ShowRanks", -1, "- shows motd with available ranks");
	register_clcmd("say_team /ranks", "ShowRanks", -1, "- shows motd with available ranks");
	
	register_concmd("ranks_reload", "ReloadRanks", ADMIN_FLAG, "- reloads ranks");
	
	g_pCvarDiff = create_cvar("ranks_diffrence", "0", FCVAR_NONE, "Disables/enables setting a rank for player by subtracting his frags with his deaths", true, 0.0, true, 1.0);
	g_pCvarRank = create_cvar("ranks_show_dead", "1", FCVAR_NONE, "Disables/enables showing a player rank for dead players", true, 0.0, true, 1.0);
	register_event("DeathMsg", "DeathMsg_event", "a", "1!0");

	RegisterHamPlayer(Ham_Spawn, "OnPlayerSpawnPost", 1);

	AutoExecConfig(true, "ranks");

	bind_pcvar_num(g_pCvarRank, g_iCvarRank);
	bind_pcvar_num(g_pCvarDiff, g_iCvarDiff);

	g_hHud = CreateHudSyncObj();

	register_dictionary("ranks.txt");
	
	LoadRanks();
	CreateMotd();
}

public ReloadRanks(id, level, cid)
{
	if(!cmd_access(id, level, cid, 1))
	 	return PLUGIN_HANDLED;
	 	
	LoadRanks();
	CreateMotd();
	
	new szName[MAX_NAME_LENGTH];
	get_user_name(id, szName, charsmax(szName));
	#if defined USE_LOGS
	 	log_to_file(g_szLogFile, "%L", LANG_SERVER, "ADMIN_RELOADED_RANKS", id);
	#endif
	
	show_activity(id, szName, "%L", LANG_SERVER, "RELOADING_RANKS");

	new iPlayers[MAX_PLAYERS], iNum;
	get_players(iPlayers, iNum, "ch");
	
	for(new i=0;i<iNum;i++)
	{
		CheckLevel(iPlayers[i]);
	}

	return PLUGIN_HANDLED;
}

public OnPlayerSpawnPost(id)
{
	if(!task_exists(TASK+id))
	{
	 	SetTask(id);
	}
}

public CreateMotd()
{
	new iLen;
	iLen += formatex(g_szMotd, charsmax(g_szMotd), "<html><body bgcolor=^"%s^"><center><font color=^"%s^" size=^"%d^">", BG_COLOR, FONT_COLOR, FONT_SIZE);
	
	for(new i=0;i<g_iLoaded;i++)
	{
		if(!i)
			iLen += formatex(g_szMotd[iLen], charsmax(g_szMotd)-iLen, "%s -> ... - %d<br>", g_szRanks[i], g_iRanks[i]-1);  //First rank
		else if(i+1 == g_iLoaded)
			iLen += formatex(g_szMotd[iLen], charsmax(g_szMotd)-iLen, "%s -> %d - ...", g_szRanks[i], g_iRanks[i-1]); //Last rank
		else
			iLen += formatex(g_szMotd[iLen], charsmax(g_szMotd)-iLen, "%s -> %d - %d<br>", g_szRanks[i], g_iRanks[i-1], g_iRanks[i]-1);
	}
	    
	formatex(g_szMotd[iLen], charsmax(g_szMotd)-iLen, "</font></center></body></html>");
}

public ShowRanks(id)
{
	static szOutput[15];
	LookupLangKey(szOutput, charsmax(szOutput), "RANKS_MOTD_TITLE", id);
	show_motd(id, g_szMotd, szOutput);
	return PLUGIN_HANDLED_MAIN;
}

public DeathMsg_event()
{
	new attacker = read_data(1);
	new victim = read_data(2);
    
	if(attacker == victim)
	 	return;

	++g_iKills[attacker];

	if(is_user_connected(attacker) && g_iPlayerLevel[attacker] < MaxLevel)
	{
		if(g_iKills[attacker] >= g_iRanks[g_iPlayerLevel[attacker]])
		{
			formatex(g_szPlayerRank[attacker], MAX_NAME_RANK-1, g_szRanks[++g_iPlayerLevel[attacker]]);
		}
	}
	
	if(!g_iCvarDiff)
	 	return;
	
	new level = g_iPlayerLevel[victim];
		
	if(is_user_connected(victim) && --g_iKills[victim] < g_iRanks[--level] && g_iPlayerLevel[victim])
	{
	 	formatex(g_szPlayerRank[victim], MAX_NAME_RANK-1, g_szRanks[--g_iPlayerLevel[victim]]);
	}
}

public client_putinserver(id)
{
	if(is_user_bot(id) || is_user_hltv(id))
	{
		NoShowSet(id);
		return;
	}

	set_task(1.0, "LoadPlayerStats", id);
}

public LoadPlayerStats(id)
{
	static stats[8], body[8];
	get_user_stats(id, stats, body);
    
	g_iKills[id] = (g_iCvarDiff) ? stats[0]-stats[1] : stats[0];
	CheckLevel(id);
	SetTask(id);
}

public client_disconnected(id, bool:drop, message[], maxlen)
{
	if(task_exists(TASK+id))
		remove_task(TASK+id)

	if(task_exists(id))
		remove_task(id);
	
	if(NoShowCheck(id))
		NoShowRemove(id);
}

public showRank(param[], tid)
{
	new id = param[0];
	if(g_iCvarRank && !is_user_alive(id))
	{
		new id2 = entity_get_int(id, EV_INT_iuser2);
        
		if(!id2 || NoShowCheck(id2))
		{
			return;
		}
        
		set_hudmessage(255, 255, 255, 0.03, 0.25, 0, 6.0, 2.0, 0.1, 0.2, 4);    
		ShowSyncHudMsg(id, g_hHud, "%l", "HUD_MSG", g_szPlayerRank[id2], g_iKills[id2]);
        
		return;
	}
    
	else if(!g_iCvarRank && !is_user_alive(id))
	{
	 	remove_task(TASK+id);
		return;
	}
    
	set_hudmessage(255, 255, 255, 0.03, 0.25, 0, 6.0, 2.0, 0.1, 0.2, 4);
	ShowSyncHudMsg(id, g_hHud, "%l", "HUD_MSG", g_szPlayerRank[id], g_iKills[id]);
}

CheckLevel(id)
{
	g_iPlayerLevel[id] = 0;
	for(new i=0;i<g_iLoaded;i++)
	{
		if(g_iKills[id] >= g_iRanks[i] && g_iPlayerLevel[id] < MaxLevel)
			++g_iPlayerLevel[id];
		else
			break;
	}
	formatex(g_szPlayerRank[id], MAX_NAME_RANK-1, g_szRanks[g_iPlayerLevel[id]])
}

LoadRanks()
{
	g_iLoaded = 0;
	new szDir[64];
	get_configsdir(szDir, charsmax(szDir));
	format(szDir, charsmax(szDir), "%s/%s", FILE);
	SetGlobalTransTarget(LANG_SERVER);

	#if defined USE_LOGS
	 	log_amx("%l", "LOOKING_FOR_FILE");
	#endif
	
	new hFile = fopen(szDir, "rt", false);
	if(!hFile)
	{
		set_fail_state("%l", "FILE_NOT_FOUND", szDir);
		return;
	}
  
  	#if defined USE_LOGS
  	 	log_amx("%l", "FILE_FOUND");
 	#endif
    
	new szLine[64], szName[MAX_NAME_RANK], szKills[33];
	while(!feof(hFile))
	{
		fgets(hFile, szLine, charsmax(szLine));
	 	trim(szLine);
	 	
		parse(szLine, szName, MAX_NAME_RANK-1, szKills, charsmax(szKills));
        
		if(!szLine[0] || szLine[0] == ';' || szLine[0] == '/')
			continue;
        
		formatex(g_szRanks[g_iLoaded], MAX_NAME_RANK-1, szName);
		g_iRanks[g_iLoaded] = str_to_num(szKills)
        
		if(++g_iLoaded >= MAX_RANKS)
		{
		 	#if defined AMX_LOGS
			 	log_amx("%l", "LIMIT_REACHED", MAX_RANKS);
			#endif
			break;
		}
		
		#if defined USE_LOGS
		 	log_amx("%l", "LOADED_RANK", szName);
		#endif
	}
	#if defined USE_LOGS
	 	log_amx("%l", "LOADED_RANKS", g_iLoaded);
	#endif
	fclose(hFile);
}

SetTask(id)
{
 	new param[1]; param[0] = id;
 	set_task(1.0, "showRank", TASK+id, param, 1, "b");
}
