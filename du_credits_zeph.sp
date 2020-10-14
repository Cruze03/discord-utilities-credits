#include <sourcemod>
#include <discord_utilities>
#include <multicolors>
#include <store>

#pragma semicolon 1
#pragma newdecls required

char g_sTableName[64];
Database g_hDB;
bool g_bIsMySQL;

bool g_bGotCredits[MAXPLAYERS+1];
char g_sServerPrefix[128];

ConVar g_cCredits;

public Plugin myinfo = 
{
	name = "Discord Utilities: Credits",
	author = "Cruze",
	description = "Give credits to users that are verified!",
	version = "1.1",
	url = "http://steamcommunity.com/profiles/76561198132924835"
};

public void OnPluginStart()
{
	g_cCredits = CreateConVar("sm_du_verified_credits", "5000", "Credits to get when player is verified.");
}

public void DU_OnLinkedAccount(int client, const char[] userid, const char[] username, const char[] discriminator)
{
	if(g_bGotCredits[client])
	{
		return;
	}
	GiveCreditsNUpdatePlayer(client);
}

public void OnConfigsExecuted()
{
	CreateTimer(3.0, Timer_OnConfigsExecuted, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_OnConfigsExecuted(Handle timer)
{
	char sDTB[32];
	FindConVar("sm_du_database_name").GetString(sDTB, sizeof(sDTB));
	FindConVar("sm_du_table_name").GetString(g_sTableName, sizeof(g_sTableName));
	FindConVar("sm_du_server_prefix").GetString(g_sServerPrefix, sizeof(g_sServerPrefix));
	SQL_TConnect(SQLQuery_Connect, sDTB);
}

public int SQLQuery_Connect(Handle owner, Handle hndl, char[] error, any data)
{
	if(hndl == INVALID_HANDLE)
	{
		LogError("[DU-Credits-Connect] Database failure: %s", error);
		SetFailState("[Discord Utilities] Failed to connect to database");
	}
	else
	{
		g_hDB = view_as<Database>(hndl);
		
		char buffer[512];
		SQL_GetDriverIdent(SQL_ReadDriver(g_hDB), buffer, sizeof(buffer));
		g_bIsMySQL = StrEqual(buffer, "mysql", false) ? true : false;
		
		if(g_bIsMySQL)
		{
			g_hDB.Format(buffer, sizeof(buffer), "ALTER TABLE `%s` ADD COLUMN IF NOT EXISTS `gotCredits` INT NOT NULL DEFAULT 0 AFTER `last_accountuse`;", g_sTableName);
		}
		else
		{
			g_hDB.Format(buffer, sizeof(buffer), "ALTER TABLE %s ADD COLUMN gotCredits int(5) DEFAULT '0'", g_sTableName);
		}
		SQL_TQuery(g_hDB, SQLQuery_ConnectCallback, buffer);
	}
}

public int SQLQuery_ConnectCallback(Handle owner, Handle hndl, char[] error, any data)
{
	if(hndl == INVALID_HANDLE)
	{
		if(!g_bIsMySQL && StrContains(error, "duplicate", false) != -1)
		{
			return;
		}
		LogError("[DU-Credits-ConnectCallback] Database failure: %s", error);
		return;
	}
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			OnClientPostAdminCheck(i);
		}
	}
}

public void OnClientPutInServer(int client)
{
	g_bGotCredits[client] = true;
}

public void OnClientPostAdminCheck(int client)
{
	if(g_hDB == null || IsFakeClient(client))
	{
		return;
	}
	char Query[128], steamid[32];
	GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));
	g_hDB.Format(Query, sizeof(Query), "SELECT gotCredits, member FROM %s WHERE steamid = '%s'", g_sTableName, steamid);
	SQL_TQuery(g_hDB, SQLQuery_OnClientPostAdminCheck, Query, GetClientUserId(client));
}

public int SQLQuery_OnClientPostAdminCheck(Handle owner, Handle hndl, char[] error, any data)
{
	if(hndl == INVALID_HANDLE)
	{
		LogError("[DU-Credits-OnClientPostAdminCheck] Database failure: %s", error);
	}
	int client;
	bool bMember;
	if((client = GetClientOfUserId(data)) == 0)
	{
		return;
	}
	while(SQL_FetchRow(hndl))
	{
		g_bGotCredits[client] = !!SQL_FetchInt(hndl, 0);
		bMember = !!SQL_FetchInt(hndl, 1);
	}
	if(!g_bGotCredits[client] && bMember)
	{
		GiveCreditsNUpdatePlayer(client);
	}
}

void GiveCreditsNUpdatePlayer(int client)
{
	char steamid[32], Query[256];
	GetClientAuthId(client, AuthId_Steam2, steamid, sizeof(steamid));

	if(g_bIsMySQL)
	{
		g_hDB.Format(Query, sizeof(Query), "UPDATE `%s` SET gotCredits = '1' WHERE `steamid` = '%s';", g_sTableName, steamid);
	}
	else
	{
		g_hDB.Format(Query, sizeof(Query), "UPDATE %s SET gotCredits = '1' WHERE steamid = '%s';", g_sTableName, steamid);
	}

	SQL_TQuery(g_hDB, SQLQuery_UpdatePlayer, Query, GetClientUserId(client));
}

public int SQLQuery_UpdatePlayer(Handle owner, Handle hndl, char[] error, any data)
{
	if(hndl == INVALID_HANDLE)
	{
		LogError("[DU-Credits-UpdatePlayer] Database failure: %s", error);
	}
	int client;
	if((client = GetClientOfUserId(data)) == 0)
	{
		return;
	}
	Store_AddCredits(client, g_cCredits.IntValue);
	g_bGotCredits[client] = true;
	CPrintToChat(client, "%s You have received {green}%d{default} credits for verifying your discord account! Thank you!", g_sServerPrefix, g_cCredits.IntValue);
}

stock void Store_AddCredits(int client, int amount)
{
	Store_SetClientCredits(client, Store_GetClientCredits(client)+amount);
}
