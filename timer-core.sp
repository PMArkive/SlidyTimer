#include <sourcemod>
#include <slidy-timer>

public Plugin myinfo = 
{
	name = "Slidy's Timer - Zones component",
	author = "SlidyBat",
	description = "Zones component of Slidy's Timer",
	version = TIMER_PLUGIN_VERSION,
	url = ""
}

Database    g_hDatabase;

float       g_fFrameTime;

Handle      g_hForward_OnDatabaseReady;

int         g_nPlayerFrames[MAXPLAYERS + 1];
bool        g_bTimerRunning[MAXPLAYERS + 1]; // whether client timer is running or not, regardless of if its paused
bool        g_bTimerPaused[MAXPLAYERS + 1];

public void OnPluginStart()
{
	/* Forwards */
	g_hForward_OnDatabaseReady = CreateGlobalForward( "Timer_OnDatabaseReady", ET_Event );
	
	SQL_DBConnect();
	
	g_fFrameTime = GetTickInterval()
}

public APLRes AskPluginLoad2( Handle myself, bool late, char[] error, int err_max )
{
	CreateNative( "Timer_GetDatabase", Native_GetDatabase );
	CreateNative( "Timer_StopTimer", Native_StopTimer );
	CreateNative( "Timer_FinishTimer", Native_FinishTiemr );

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary( "timer-core" );

	return APLRes_Success;
}

public void OnPlayerRunCmd( int client, int& buttons )
{
	if( g_bTimerRunning[client] && !g_bTimerPaused[client] )
	{
		g_nPlayerFrames[client]++;
	}
}


void StartTimer( int client )
{
	g_nPlayerFrames[client] = 0;
	g_bTimerRunning[client] = true;
	g_bTimerPaused[client] = false;
}

void StopTimer( int client )
{
	g_bTimerRunning[client] = false;
	g_bTimerPaused[client] = false;
}

void FinishTimer( int client )
{
	//float time = g_nPlayerFrames[client] * g_fFrameTime;
	StopTimer( client );
	//ZoneTrack track = Timer_GetClientZoneTrack( client );
	
	// save time for track
}

public void OnEnterZone( int client, int id, ZoneType zoneType, ZoneTrack zoneTrack, int subindex )
{
	if( zoneType == Zone_Start )
	{
		StartTimer( client );
	}
	else if( zoneType == Zone_End && !g_bTimerPaused[client] && Timer_GetClientZoneTrack( client ) == zoneTrack )
	{
		FinishTimer( client );
	}
	else if( zoneType == Zone_Cheatzone && g_bTimerRunning[client] )
	{
		StopTimer( client );
	}
}


/* Database stuff */

void SQL_DBConnect()
{
	delete g_hDatabase;
	
	char[] error = new char[255];
	g_hDatabase = SQL_Connect( "Slidy-Timer", true, error, 255 );

	if( g_hDatabase == null )
	{
		SetFailState( "[SQL ERROR] (SQL_DBConnect) - %s", error );
	}
	
	// support unicode names
	g_hDatabase.SetCharset( "utf8" );

	Call_StartForward( g_hForward_OnDatabaseReady );
	Call_Finish();
	
	SQL_CreateTables();
}

void SQL_CreateTables()
{
	Transaction txn = new Transaction();
	
	char query[512];
	
	Format( query, sizeof( query ), "CREATE TABLE IF NOT EXISTS `t_players` ( uid INT NOT NULL AUTO_INCREMENT, steamid VARCHAR( 64 ) NOT NULL, lastname VARCHAR( 128 ) NOT NULL, lastserver VARCHAR( 8 ) NOT NULL, firstconnect INT( 16 ) NOT NULL, lastconnect INT( 16 ) NOT NULL, prestigetokens INT NOT NULL, season INT NOT NULL, vip INT( 3 ) NOT NULL, vipend INT NOT NULL, PRIMARY KEY ( `uid` ) );" );
	txn.AddQuery( query );
	
	Format( query, sizeof( query ), "CREATE TABLE IF NOT EXISTS `t_records` ( mapname VARCHAR( 128 ) NOT NULL, uid INT NOT NULL, time INT( 8 ) NOT NULL, sync FLOAT NOT NULL, strafesync FLOAT NOT NULL, jumps INT NOT NULL, strafes INT NOT NULL, style INT NOT NULL, zonegroup INT NOT NULL, server VARCHAR( 18 ) NOT NULL, timestamp INT( 16 ) NOT NULL, PRIMARY KEY ( `mapname`, `uid`, `style`, `zonegroup` ) );" );
	txn.AddQuery( query );
	
	g_hDatabase.Execute( txn, SQL_OnCreateTableSuccess, SQL_OnCreateTableFailure, _, DBPrio_High );
}

public void SQL_OnCreateTableSuccess( Database db, any data, int numQueries, DBResultSet[] results, any[] queryData )
{
	SQL_LoadPlayerData();
}

public void SQL_OnCreateTableFailure( Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData )
{
	SetFailState( "[SQL ERROR] (SQL_CreateTables) - %s", error );
}

void SQL_LoadPlayerData()
{
	// TODO: decide what to do here
}


/* Natives */

public int Native_GetDatabase( Handle handler, int numParams )
{
	SetNativeCellRef( 1, g_hDatabase );
}

public int Native_StopTimer( Handle handler, int numParams )
{
	StartTimer( GetNativeCell( 1 ) );
}

public int Native_FinishTimer( Handle handler, int numParams )
{
	FinishTimer( GetNativeCell( 1 ) );
}