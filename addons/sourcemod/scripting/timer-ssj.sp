#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <clientprefs>
#include <slidy-timer>

enum (<<= 1)
{
	SSJ_JUMPNUMBER = 1,
	SSJ_PRESPEED,
	SSJ_SPEED,
	SSJ_DELTASPEED,
	SSJ_SYNC,
	SSJ_STRAFETIME,
	SSJ_GAIN,
	SSJ_EFFICIENCY,
	SSJ_DELTAHEIGHT,
	SSJ_DELTATIME
}

#define TOTAL_SSJ_SETTINGS 10
#define DEFAULT_SSJ_SETTINGS SSJ_PRESPEED | SSJ_JUMPNUMBER | SSJ_SPEED | SSJ_SYNC | SSJ_DELTASPEED | SSJ_DELTATIME

#define MAX_SSJ_JUMP_INTERVAL 25
#define SSJ_RESET_TICKS 10

enum
{
	FSOLID_CUSTOMRAYTEST		= 0x0001,	// Ignore solid type + always call into the entity for ray tests
	FSOLID_CUSTOMBOXTEST		= 0x0002,	// Ignore solid type + always call into the entity for swept box tests
	FSOLID_NOT_SOLID			= 0x0004,	// Are we currently not solid?
	FSOLID_TRIGGER				= 0x0008,	// This is something may be collideable but fires touch functions
											// even when it's not collideable (when the FSOLID_NOT_SOLID flag is set)
	FSOLID_NOT_STANDABLE		= 0x0010,	// You can't stand on this
	FSOLID_VOLUME_CONTENTS		= 0x0020,	// Contains volumetric contents (like water)
	FSOLID_FORCE_WORLD_ALIGNED	= 0x0040,	// Forces the collision rep to be world-aligned even if it's SOLID_BSP or SOLID_VPHYSICS
	FSOLID_USE_TRIGGER_BOUNDS	= 0x0080,	// Uses a special trigger bounds separate from the normal OBB
	FSOLID_ROOT_PARENT_ALIGNED	= 0x0100,	// Collisions are defined in root parent's local coordinate space
	FSOLID_TRIGGER_TOUCH_DEBRIS	= 0x0200,	// This trigger will touch debris objects
}

char g_cSSJSettingNames[TOTAL_SSJ_SETTINGS][] = 
{
	"Jump Number",
	"Prespeed",
	"Speed",
	"Δ Speed",
	"Sync",
	"Strafe %",
	"Gain",
	"Efficiency",
	"Δ Height",
	"Δ Time"
};

enum SSJStats
{
	Float:SSJ_Speed,
	Float:SSJ_Pos[3],
	SSJ_Tick,
	SSJ_SyncedTicks,
	SSJ_StrafedTicks
}

Handle g_hCookieSettings;
int g_Settings[MAXPLAYERS + 1];

Handle g_hCookieJumpInterval;
int g_iJumpInterval[MAXPLAYERS + 1];

Handle g_hCookieSSJEnabled;
bool g_bSSJEnabled[MAXPLAYERS + 1];

int g_nJumps[MAXPLAYERS + 1];
int g_nSyncedTicks[MAXPLAYERS + 1];
int g_nStrafedTicks[MAXPLAYERS + 1];

bool g_bTouchesWall[MAXPLAYERS + 1];
int g_nTouchTicks[MAXPLAYERS + 1];
float g_fTotalGain[MAXPLAYERS + 1];
float g_fDistanceTravelled[MAXPLAYERS + 1];
int g_nGroundTicks[MAXPLAYERS + 1];

ArrayList g_aJumpStats[MAXPLAYERS + 1];

public Plugin myinfo = 
{
	name = "Slidy's Timer - SSJ",
	author = "SlidyBat",
	description = "SSJ plugin for Slidy's Timer",
	version = TIMER_PLUGIN_VERSION,
	url = ""
}

public void OnPluginStart()
{
	g_hCookieSettings = RegClientCookie( "sm_ssj_settings", "SSJ settings", CookieAccess_Protected );
	g_hCookieJumpInterval = RegClientCookie( "sm_ssj_jumpinterval", "SSJ jump interval", CookieAccess_Protected );

	RegConsoleCmd( "sm_ssj", Command_SSJ );
}

public void OnMapStart()
{
	HookEvent( "player_jump", HookEvent_PlayerJump );
}

public void OnClientPutInServer( int client )
{
	SDKHook( client, SDKHook_Touch, Hook_OnTouch );

	if( !GetClientCookieInt( client, g_hCookieSettings, g_Settings[client] ) )
	{
		g_Settings[client] = DEFAULT_SSJ_SETTINGS;
		SetClientCookieInt( client, g_hCookieSettings, DEFAULT_SSJ_SETTINGS );
	}

	if( !GetClientCookieInt( client, g_hCookieJumpInterval, g_iJumpInterval[client] ) )
	{
		g_iJumpInterval[client] = 6;
		SetClientCookieInt( client, g_hCookieJumpInterval, 6 );
	}

	if( !GetClientCookieBool( client, g_hCookieSSJEnabled, g_bSSJEnabled[client] ) )
	{
		g_bSSJEnabled[client] = false;
		SetClientCookieBool( client, g_hCookieSSJEnabled, false );
	}

	ResetStats( client );
}

public Action OnPlayerRunCmd( int client, int& buttons, int& impulse, float vel[3], float angles[3] )
{
	static float s_LastAngles[MAXPLAYERS + 1][3];

	float deltayaw = NormalizeAngle( angles[1] - s_LastAngles[client][1] );

	if( GetEntityFlags( client ) & FL_ONGROUND )
	{
		if( ++g_nGroundTicks[client] > SSJ_RESET_TICKS )
		{
			ResetStats( client );
		}
	}
	else
	{
		g_nGroundTicks[client] = 0;
		GetStats( client, vel, angles, deltayaw );
	}

	if( g_bTouchesWall[client] )
	{
		g_nTouchTicks[client]++;
		g_bTouchesWall[client] = false;
	}
	else
	{
		g_nTouchTicks[client] = 0;
	}

	s_LastAngles[client][0] = angles[0];
	s_LastAngles[client][1] = angles[1];
	s_LastAngles[client][2] = angles[2];
}

public Action Hook_OnTouch( int client, int entity )
{
	if( !( GetEntProp( entity, Prop_Data, "m_usSolidFlags" ) & (FSOLID_NOT_SOLID|FSOLID_TRIGGER) ) )
	{
		g_bTouchesWall[client] = true;
	}
}

public Action HookEvent_PlayerJump( Event event, const char[] name, bool dontBroadcast )
{
	int client = GetClientOfUserId( event.GetInt( "userid" ) );

	float pos[3];
	GetClientAbsOrigin( client, pos );

	any stats[SSJStats];
	stats[SSJ_Speed] = GetClientSpeed( client );
	stats[SSJ_Tick] = GetGameTickCount();
	stats[SSJ_Pos][0] = pos[0];
	stats[SSJ_Pos][1] = pos[1];
	stats[SSJ_Pos][2] = pos[2];
	stats[SSJ_SyncedTicks] = g_nSyncedTicks[client];
	stats[SSJ_StrafedTicks] = g_nStrafedTicks[client];

	g_aJumpStats[client].PushArray( stats[0] );

	if( g_aJumpStats[client].Length > MAX_SSJ_JUMP_INTERVAL )
	{
		g_aJumpStats[client].Erase( 0 );
	}

	if( g_nJumps[client] == 1 && g_Settings[client] & SSJ_PRESPEED )
	{
		PrintToChat( client, "[Timer] Prespeed: %.2f", stats[SSJ_Speed] );
	}
	else if( ++g_nJumps[client] % g_iJumpInterval[client] == 0 )
	{
		PrintStats( client );

		g_fDistanceTravelled[client] = 0.0;
		g_fTotalGain[client] = 0.0;
	}
}

public Action Command_SSJ( int client, int args )
{
	OpenSSJMenu( client );

	return Plugin_Handled;
}

void ResetStats( int client )
{
	delete g_aJumpStats[client];
	g_aJumpStats[client] = new ArrayList( view_as<int>(SSJStats) );

	g_nJumps[client] = 0;
	g_nSyncedTicks[client] = 0;
	g_nStrafedTicks[client] = 0;
}

void GetStats( int client, float vel[3], float angles[3], float deltayaw )
{
	if( deltayaw != 0.0 )
	{
		g_nStrafedTicks[client]++;
	}

	float absvel[3];
	GetEntPropVector( client, Prop_Data, "m_vecAbsVelocity", absvel );
	absvel[2] = 0.0;

	g_fDistanceTravelled[client] += GetVectorLength( absvel ) * GetTickInterval() * GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue");

	float fore[3], side[3], wishvel[3], wishdir[3];
	float wishspeed, wishspd, currentgain;
	
	GetAngleVectors(angles, fore, side, NULL_VECTOR);
	
	fore[2] = 0.0;
	NormalizeVector(fore, fore);
	side[2] = 0.0;
	NormalizeVector(side, side);
	
	for( int i = 0; i < 2; i++ )
	{
		wishvel[i] = fore[i] * vel[0] + side[i] * vel[1];
	}

	float maxspeed = GetEntPropFloat(client, Prop_Send, "m_flMaxspeed");
	float gaincoeff;

	wishspeed = NormalizeVector(wishvel, wishdir);
	if( wishspeed > maxspeed && maxspeed != 0.0 )
	{
		wishspeed = GetEntPropFloat(client, Prop_Send, "m_flMaxspeed");
	}

	if( wishspeed )
	{
		wishspd = (wishspeed > 30.0) ? 30.0 : wishspeed;
		
		currentgain = GetVectorDotProduct( absvel, wishdir );
		if( currentgain < 30.0 )
		{
			g_nSyncedTicks[client]++;
			gaincoeff = (wishspd - FloatAbs( currentgain )) / wishspd;
		}
		if( g_bTouchesWall[client] && g_nTouchTicks[client] && gaincoeff > 0.5 )
		{
			gaincoeff -= 1;
			gaincoeff = FloatAbs(gaincoeff);
		}

		g_fTotalGain[client] += gaincoeff;
	}
}

void PrintStats( int client )
{
	int lastIdx = g_aJumpStats[client].Length - 1;
	any stats[SSJStats];
	g_aJumpStats[client].GetArray( lastIdx, stats[0] );

	any lastStats[SSJStats];
	g_aJumpStats[client].GetArray( lastIdx - g_iJumpInterval[client], lastStats[0] );

	char message[256];
	Format( message, sizeof(message), "[Timer]" );
	//"Jump Number",
	//"Prespeed",
	//"Speed",
	//"Δ Speed",
	//"Sync",
	//"Strafe %",
	//"Gain",
	//"Efficiency",
	//"Δ Height",
	//"Δ Time"

	int tickcount = stats[SSJ_Tick] - lastStats[SSJ_Tick];
	float gain = g_fTotalGain[client] / tickcount;

	if( g_Settings[client] & SSJ_JUMPNUMBER )
	{
		Format( message, sizeof(message), "%s Jump: %i", message, g_nJumps[client] );
	}
	if( g_Settings[client] & SSJ_SPEED )
	{
		Format( message, sizeof(message), "%s Speed: %.2f", message, stats[SSJ_Speed] );
	}
	if( g_Settings[client] & SSJ_DELTASPEED )
	{
		float deltaspeed = stats[SSJ_Speed] - lastStats[SSJ_Speed];
		Format( message, sizeof(message), "%s Δ Speed: %s%.2f", message, (deltaspeed > 0.0) ? "+" : "-", deltaspeed );
	}
	if( g_Settings[client] & SSJ_SYNC )
	{
		int syncedticks = stats[SSJ_SyncedTicks] - lastStats[SSJ_SyncedTicks];
		float sync = float(syncedticks) / tickcount;
		Format( message, sizeof(message), "%s Sync: %.2f", message, sync * 100.0 );
	}
	if( g_Settings[client] & SSJ_STRAFETIME )
	{
		int strafedticks = stats[SSJ_StrafedTicks] - lastStats[SSJ_StrafedTicks];
		float strafetime = float(strafedticks) / tickcount;
		Format( message, sizeof(message), "%s Jump: %.2f", message, strafetime * 100.0 );
	}
	if( g_Settings[client] & SSJ_GAIN )
	{
		Format( message, sizeof(message), "%s Gain: %.2f", message, gain * 100.0 );
	}
	if( g_Settings[client] & SSJ_EFFICIENCY )
	{
		float startpos[3];
		startpos[0] = lastStats[SSJ_Pos][0];
		startpos[1] = lastStats[SSJ_Pos][1];

		float endpos[3];
		endpos[0] = stats[SSJ_Pos][0];
		endpos[1] = stats[SSJ_Pos][1];

		float displacement[3];
		SubtractVectors( endpos, startpos, displacement );

		float efficiency = (gain * GetVectorLength( displacement )) / g_fDistanceTravelled[client];

		Format( message, sizeof(message), "%s Efficiency: %.2f", message, efficiency );
	}
	if( g_Settings[client] & SSJ_DELTAHEIGHT )
	{
		float deltaheight = stats[SSJ_Pos][2] - lastStats[SSJ_Pos][2];
		Format( message, sizeof(message), "%s Δ Height: %s%.2f", message, (deltaheight > 0.0) ? "+" : "-", deltaheight );
	}
	if( g_Settings[client] & SSJ_DELTATIME )
	{
		float time = tickcount * GetTickInterval();
		Format( message, sizeof(message), "%s Δ Time: %.2f", message, time );
	}
}

void OpenSSJMenu( int client )
{
	Menu menu = new Menu( SSJMenu_Handler );
	menu.SetTitle( "SSJ\n \n" );

	char buffer[256];

	Format( buffer, sizeof(buffer), "SSJ: %s\n \n", g_bSSJEnabled[client] ? "Enabled" : "Disabled" );
	menu.AddItem( "toggle", buffer );

	Format( buffer, sizeof(buffer), "--\n \nJump stats interval: %i", g_iJumpInterval[client] );
	menu.AddItem( "-", buffer );
	
	menu.AddItem( "+", "++\n \n" );

	menu.AddItem( "ssjsettings", "Settings" );
}

public int SSJMenu_Handler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Select )
	{
		switch( param2 )
		{
			case 0:
			{
				g_bSSJEnabled[param1] = !g_bSSJEnabled[param1];
				OpenSSJMenu( param1 );
			}
			case 1:
			{
				if( g_iJumpInterval[param1] > 1 )
				{
					g_iJumpInterval[param1]--;
				}
				OpenSSJMenu( param1 );
			}
			case 2:
			{
				if( g_iJumpInterval[param1] < MAX_SSJ_JUMP_INTERVAL )
				{
					g_iJumpInterval[param1]++;
				}
				OpenSSJMenu( param1 );
			}
			case 3:
			{
				OpenSSJSettingsMenu( param1 );
			}
		}
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}

void OpenSSJSettingsMenu( int client )
{
	Menu menu = new Menu( SSJSettingsMenu_Handler );
	menu.SetTitle( "SSJ Settings\n \n" );

	char buffer[256];
	for( int i = 0; i < TOTAL_SSJ_SETTINGS; i++ )
	{
		Format( buffer, sizeof(buffer), "%s: %s", g_cSSJSettingNames[i], (g_Settings[client] & (1 << i)) ? "Enabled" : "Disabled" );
		menu.AddItem( "ssjsetting", buffer );
	}

	menu.ExitBackButton = true;
	menu.Display( client, MENU_TIME_FOREVER );
}

public int SSJSettingsMenu_Handler( Menu menu, MenuAction action, int param1, int param2 )
{
	if( action == MenuAction_Cancel && param2 == MenuCancel_ExitBack )
	{
		OpenSSJMenu( param1 );
	}
	else if( action == MenuAction_Select )
	{
		g_Settings[param1] ^= (1 << (param2 - 1));
		OpenSSJSettingsMenu( param1 );
	}
	else if( action == MenuAction_End )
	{
		delete menu;
	}
}

stock void SetClientCookieInt( int client, Handle cookie, int value )
{
	char sValue[8];
	IntToString( value, sValue, sizeof(sValue) );

	SetClientCookie( client, cookie, sValue );
}

stock bool GetClientCookieInt( int client, Handle cookie, int& value )
{
	char sValue[8];
	GetClientCookie( client, cookie, sValue, sizeof(sValue) );

	if( sValue[0] == '\0' )
	{
		return false;
	}

	StringToInt( sValue, value );
	return true;
}

stock void SetClientCookieBool( int client, Handle cookie, bool value )
{
	SetClientCookie( client, cookie, value ? "1" : "0" );
}

stock bool GetClientCookieBool( int client, Handle cookie, bool& value )
{
	char sValue[8];
	GetClientCookie( client, cookie, sValue, sizeof(sValue) );

	if( sValue[0] == '\0' )
	{
		return false;
	}

	StringToInt( sValue, view_as<int>(value) );
	return true;
}