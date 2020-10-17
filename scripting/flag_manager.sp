#include <sourcemod>
#include <colors_csgo>

#pragma semicolon 1
#pragma newdecls required

#define CHAT_TAG "[{orange}FlagManager{default}]"

bool g_bFullyConnected;
bool g_bDbInitTriggered;

ConVar fm_adminFlag;

Database g_hDatabase = null;

public Plugin myinfo = {
	name = "Flag Manager", 
	author = "venus", 
	url = "https://github.com/ivenuss"
};

public void OnPluginStart() {
	RegConsoleCmd("sm_addflag", Cmd_AddFlag);
	RegConsoleCmd("sm_extendflag", Cmd_ExtendFlag);
	RegConsoleCmd("sm_deleteflag", Cmd_DeleteFlag);

	fm_adminFlag = CreateConVar("sm_fm_adminflag", "b", "Admin flags with access to admin commands.");
	AutoExecConfig(true, "flagmanager");
}

public void OnConfigsExecuted() {
	if (!g_bDbInitTriggered && !g_hDatabase) {
		Database.Connect(SQL_Connection, "flag_manager");
		g_bDbInitTriggered = true;
	}
}

public void OnClientPostAdminCheck(int client) {
	if (g_bFullyConnected) {
		DeleteExpiredUsers();

		if (IsValidClient(client)) {
			LoadUserFlags(client);
		}
	}
}

public void OnRebuildAdminCache(AdminCachePart part) {
	if (part == AdminCache_Overrides) {
		for (int i = 1; i <= MaxClients; i++) {
			if (!IsValidClient(i)) continue;
			
			LoadUserFlags(i);
		}
	}
}

public Action Cmd_AddFlag(int client, int args) {
	if (!HasImmunity(client)) {
		if (IsValidClient(client)) {
			CPrintToChat(client, "%s You don't have access to this command", CHAT_TAG);
		}

		return Plugin_Handled;
	}
	char szQuery[256], szTargetSteamid[25], szAdminFlags[20], szUnit[30];

	GetCmdArg(1, szTargetSteamid, sizeof(szTargetSteamid));
	GetCmdArg(2, szAdminFlags, sizeof(szAdminFlags));
	int iDuration = GetCmdArgInt(3);
	GetCmdArg(4, szUnit, sizeof(szUnit));

	if (!IsSteamId64(szTargetSteamid) || iDuration < 0 || !IsValidUnit(szUnit) || args < 3) {
		if (IsValidClient(client)) {
			CPrintToChat(client, "%s Usage: sm_addflag <{red}steamid64{default}> <{red}flag{default}> <{red}duration{default}> <{red}unit{default}>", CHAT_TAG);
		}

		return Plugin_Handled;
	}

	if (iDuration == 0) {
		// Now we are adding user to database with flag perma
		g_hDatabase.Format(szQuery, sizeof(szQuery), "INSERT IGNORE INTO flag_manager (steamid, flags, date, expiration_date) VALUES ('%s', '%s', NOW(), NULL)", szTargetSteamid, szAdminFlags);
	} else {
		// Now we are adding user to database with flag duration
		g_hDatabase.Format(szQuery, sizeof(szQuery), "INSERT IGNORE INTO flag_manager (steamid, flags, date, expiration_date) VALUES ('%s', '%s', NOW(), NOW() + INTERVAL %d %s)", szTargetSteamid, szAdminFlags, iDuration, szUnit);
	}
	
	g_hDatabase.Query(SQL_Error, szQuery);

	//If user is already in server, we'll load him his flags otherwise they'll be loaded on OnClientPostAdminCheck
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsValidClient(i)) continue;

		char szLoopedSteamId[21];
		GetClientAuthId(i, AuthId_SteamID64, szLoopedSteamId, sizeof(szLoopedSteamId));

		if (StrEqual(szLoopedSteamId, szTargetSteamid, false)) {
			LoadUserFlags(i);
			CPrintToChat(i, "%s You recieved new admin flags.", CHAT_TAG);
		}
	}

	return Plugin_Handled;
}

public Action Cmd_ExtendFlag(int client, int args) {
	if (!HasImmunity(client)) {
		if (IsValidClient(client)) {
			CPrintToChat(client, "%s You don't have access to this command", CHAT_TAG);
		}

		return Plugin_Handled;
	}

	char szQuery[256], szTargetSteamid[25], szUnit[30];
	GetCmdArg(1, szTargetSteamid, sizeof(szTargetSteamid));
	int iDuration = GetCmdArgInt(2);
	GetCmdArg(3, szUnit, sizeof(szUnit));
	
	if (!IsSteamId64(szTargetSteamid) || iDuration < 0 || !IsValidUnit(szUnit) || args < 2) {
		PrintToChatAll("result %b", IsSteamId64(szTargetSteamid));
		if (IsValidClient(client)) {
			CPrintToChat(client, "%s Usage: sm_extendflag <{red}steamid64{default}> <{red}duration{default}> <{red}unit{default}>", CHAT_TAG);
		}
		return Plugin_Handled;
	}

	if (iDuration == 0) {
		// Now we are updating user expiration date to perma
		g_hDatabase.Format(szQuery, sizeof(szQuery), "UPDATE flag_manager SET expiration_date = NULL WHERE steamid = '%s'", szTargetSteamid);
	} else {
		// Now we are updating user expiration date to chosen date
		g_hDatabase.Format(szQuery, sizeof(szQuery), "UPDATE flag_manager SET expiration_date = expiration_date + INTERVAL %d %s WHERE steamid = '%s'", iDuration, szUnit, szTargetSteamid);
	}
	
	g_hDatabase.Query(SQL_Error, szQuery);

	return Plugin_Handled;
}

public Action Cmd_DeleteFlag(int client, int args) {
	if (!HasImmunity(client)) {
		if (IsValidClient(client)) {
			CPrintToChat(client, "%s You don't have access to this command", CHAT_TAG);
		}

		return Plugin_Handled;
	}

	char szTargetSteamid[25];
	GetCmdArg(1, szTargetSteamid, sizeof(szTargetSteamid));

	if (!IsIntenger(szTargetSteamid) || strlen(szTargetSteamid) < 17 || args < 1) {
		if (IsValidClient(client)) {
			CPrintToChat(client, "%s Usage: sm_deleteflag <{red}steamid64{default}>", CHAT_TAG);
		}
		return Plugin_Handled;
	}

	char szQuery[256];
	//Now we are deleting user from database
	g_hDatabase.Format(szQuery, sizeof(szQuery), "DELETE FROM flag_manager WHERE steamid = '%s'", szTargetSteamid);
	g_hDatabase.Query(SQL_Error, szQuery);

	ServerCommand("sm_reloadadmins"); //If user flag is deleted, reload admin flags

	return Plugin_Handled;
}

stock bool HasImmunity(int client) {
	if (client == 0) return true;

	int iFlagBits = GetUserFlagBits(client);
	
	if (iFlagBits > 0) {
		char szFlags[32];
		GetConVarString(fm_adminFlag, szFlags, sizeof(szFlags));
		
		if (iFlagBits & (ReadFlagString(szFlags) | ADMFLAG_ROOT) > 0 && !StrEqual(szFlags, "")) {
			return true;
		}
	}
	
	return false;
}

stock bool IsIntenger(char[] buffer) {
	int len = strlen(buffer);
	for (int i = 1; i < len; i++) {
		if (!IsCharNumeric(buffer[i])) {
			return false;
		}
	}
	return true;
}

stock bool IsValidUnit(char[] unit) {
	return (
		StrEqual(unit, "", false) ||
		StrEqual(unit, "SECOND", false) ||
		StrEqual(unit, "MINUTE", false) ||
		StrEqual(unit, "HOUR", false) ||
		StrEqual(unit, "DAY", false) ||
		StrEqual(unit, "WEEK", false) ||
		StrEqual(unit, "MONTH", false) ||
		StrEqual(unit, "YEAR", false)
	);
}

stock bool IsSteamId64(char[] steamid64) {
	return (IsIntenger(steamid64) && strlen(steamid64) == 17);
}

stock bool IsValidClient(int client) {
	return (0 < client && client <= MaxClients && IsClientInGame(client) && IsFakeClient(client) == false);
}

/* 
	SQL Stuff
*/
void LoadUserFlags(int client) {
	char szQuery[256], szSteamID[21];

	if (!GetClientAuthId(client, AuthId_SteamID64, szSteamID, sizeof(szSteamID))) {
		LogError("Player %N's steamid couldn't be fetched", client);
	}

	//Whenever user joins server we check if he has any reserved admin flags
	g_hDatabase.Format(szQuery, sizeof(szQuery), "SELECT flags, joined FROM flag_manager WHERE steamid = '%s'", szSteamID);
	g_hDatabase.Query(SQL_Authorization, szQuery, GetClientUserId(client));
}

void DeleteExpiredUsers() {
	char szQuery[256];
	//Everytime someones join it will auto. delete all outdated users
	g_hDatabase.Format(szQuery, sizeof(szQuery), "DELETE FROM flag_manager WHERE expiration_date < NOW() AND NOT(ISNULL(expiration_date))");
	g_hDatabase.Query(SQL_Error, szQuery);

	ServerCommand("sm_reloadadmins"); //If user flag is deleted, reload admin flags
}

public void SQL_Authorization(Database database, DBResultSet results, const char[] error, int data) {
	if (results == null) {
		SetFailState(error);
	}

	int client = GetClientOfUserId(data);
	if (IsValidClient(client)) {
		if (results.RowCount != 0) {
			char szUserFlags[32];

			results.FetchRow();
			results.FetchString(0, szUserFlags, sizeof(szUserFlags));

			SetUserFlagBits(client, GetUserFlagBits(client) | ReadFlagString(szUserFlags)); //Set user admin flag

			bool bJoined = !!results.FetchInt(1);
			if (!bJoined) { //If user haven't joined server with VIP this will automatically update table to joined = 1
				char szSteamID[21];
				if(!GetClientAuthId(client, AuthId_SteamID64, szSteamID, sizeof(szSteamID))) {
					LogError("Player %N's steamid couldn't be fetched", client);
					return;
				}

				char szQuery[256];
				g_hDatabase.Format(szQuery, sizeof(szQuery), "UPDATE flag_manager SET joined = 1 WHERE steamid = '%s'", szSteamID);
				g_hDatabase.Query(SQL_Error, szQuery, GetClientUserId(client));
			}
		}
	}
}

public void SQL_Connection(Database database, const char[] error, int data) {
	if (database == null) {
		SetFailState(error);
	} else {
		g_hDatabase = database;

		g_hDatabase.SetCharset("utf8mb4");

		g_hDatabase.Query(SQL_CreateCallback, "\
		CREATE TABLE IF NOT EXISTS `flag_manager` ( \
			`steamid` VARCHAR(21) NOT NULL COLLATE 'utf8mb4_unicode_ci', \
			`flags` VARCHAR(20) NOT NULL COLLATE 'utf8mb4_unicode_ci', \
			`date` DATETIME NULL DEFAULT NULL, \
			`expiration_date` DATETIME NULL DEFAULT NULL, \
			`joined` TINYINT(2) NOT NULL DEFAULT 0, \
			UNIQUE INDEX `steamid` (`steamid`) USING BTREE \
		) \
		COLLATE='utf8mb4_unicode_ci' \
		ENGINE=InnoDB \
		;");
	}
}

public void SQL_CreateCallback(Database datavas, DBResultSet results, const char[] error, int data) {
	if (results == null) {
		SetFailState(error);
	}

	g_bFullyConnected = true;

	// Late load
	for (int i = 1; i <= MaxClients; i++) {
		if (IsValidClient(i)) return;
		
		OnClientPostAdminCheck(i);
	}
}

public void SQL_Error(Database datavas, DBResultSet results, const char[] error, int data) {
	if (results == null) {
		SetFailState(error);
	}
}
