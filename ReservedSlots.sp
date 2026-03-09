#include <sourcemod>
#include <PTaH>
#include <server_redirect>

#pragma newdecls required
#pragma semicolon 1

ConVar g_cKickType, g_cPluginEnabled, g_cKickReason ,g_cServerReason, g_cKickEnabled, g_cRedirectEnabled, g_hRedirect;
char g_sServerIP[24];

public Plugin myinfo = 
{
	name 		= 	"Reserved slots using PTaH and MaxClients Kicker",
	author 		= 	"Nano, Letaryat",
	description 	= 	"Kick or redirects to another server non-vips when a vip joins, and prevents players from exceeding the max-slots player limit.",
	version 		= 	"2.1",
	url 			= 	"https://steamcommunity.com/id/marianzet1/"
}

public void OnPluginStart()
{
	g_cPluginEnabled		=	CreateConVar("sm_reserved_slots_enabled", 	"1", "Enables/disables the whole plugin", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cKickEnabled 		= 	CreateConVar("sm_reserved_slots_kick", 		"1", "1 - Enable VIP connect kick method only, 0 - Disable VIP connect kick method only.");
	g_cKickType 			= 	CreateConVar("sm_reserved_slots_type", 		"1", "Who gets kicked out: 1 - Highest ping player, 2 - Longest connection time player, 3 - Random player, 4 - Shortest connection time player", FCVAR_NONE, true, 1.0, true, 4.0);
	
	g_cKickReason			= 	CreateConVar("sm_reserved_slots_reason", "You were kicked because a VIP joined.", "Reason used when kicking players");
	g_cServerReason		= 	CreateConVar("sm_reserved_slots_fullserverreason", "Server is full! Try to join later, please.", "Reason used when someone without privileges join");

	g_cRedirectEnabled		=	CreateConVar("sm_redirect_slots_enabled", 	"1", "Enables/disables redirection to another server", FCVAR_NONE, true, 0.0, true, 1.0);
	g_hRedirect = CreateConVar("sm_redirect_server", "192.168.0.1:27015", "server ip to which the player will automatically redirected");
	g_hRedirect.AddChangeHook(Change_);

	ParseRedirectIP();

	AutoExecConfig(true, "ReservedSlots");
	LoadTranslations("reservedslots.phrases");
	
	PTaH(PTaH_ClientConnectPre, Hook, Hook_OnClientConnect);
}

public void Change_ (ConVar convar, const char[] oldValue, const char[] newValue)
{
	ParseRedirectIP();
}

void ParseRedirectIP()
{
	g_hRedirect.GetString(g_sServerIP, sizeof g_sServerIP);

}

public Action Timer_Redirect(Handle timer, any client)
{
	if (IsClientInGame(client))
	{
		RedirectClient(client, g_sServerIP);
	}

	return Plugin_Stop;
}

void RedirectWithDelay(int client)
{
	if (!IsClientInGame(client))
		return;

	PrintToChat(client, "%t", "RedirectMessage");

	CreateTimer(6.0, Timer_Redirect, client);
}

public Action Hook_OnClientConnect(int iAccountID, const char[] sIp, const char[] sName, char sPassword[128], char rejectReason[255])
{
	if (!g_cPluginEnabled.BoolValue || !g_cKickEnabled.BoolValue)
	{
		return Plugin_Continue;
	}

	if(GetClientCount(false) > (GetMaxHumanPlayers() - 1))
	{
		char sSteamID[64];
		FormatEx(sSteamID, sizeof sSteamID, "STEAM_1:%d:%d", iAccountID & 1, iAccountID >>> 1);

		AdminId aAdmin = FindAdminByIdentity(AUTHMETHOD_STEAM, sSteamID);
		if (aAdmin == INVALID_ADMIN_ID)
		{
			return Plugin_Continue;
		}

		if (GetAdminFlag(aAdmin, Admin_Reservation))
		{
			int iTarget = SelectKickClient();
			if (iTarget)
			{
				GetConVarString(g_cKickReason, rejectReason, sizeof(rejectReason));
				
				if(g_cRedirectEnabled.BoolValue)
				{
					//RedirectClient(iClient, g_sServerIP);
					RedirectWithDelay(iTarget);
				}
				else
				{
					KickClient(iTarget, "%s", rejectReason);
				}

				//KickClientEx(iTarget, "%s", rejectReason);
				//RedirectClient(iClient, g_sServerIP);
			}
		}
	}
	return Plugin_Continue;
}

int SelectKickClient()
{	
	float fHighestValue, fHighestSpecValue, fValue;
	int iHighestValueId, iHighestSpecValueId;
	bool bSpecFound;
	
	for (int i = 1; i <= MaxClients; i++)
	{	
		if (!IsClientConnected(i))
		{
			continue;
		}
	
		int iFlags = GetUserFlagBits(i);
		
		if (IsFakeClient(i) || IsClientSourceTV(i) || IsClientReplay(i) || iFlags & ADMFLAG_ROOT || iFlags & ADMFLAG_RESERVATION || CheckCommandAccess(i, "sm_reskick_immunity", ADMFLAG_RESERVATION, false))
		{
			continue;
		}
		
		fValue = 0.0;
			
		if (IsClientInGame(i))
		{
			int iType = g_cKickType.IntValue;

			if(iType == 1)
			{
				fValue = GetClientAvgLatency(i, NetFlow_Outgoing);
			}
			else if(iType == 2)
			{
				fValue = GetClientTime(i);
			}
			else if(iType == 3)
			{
				fValue = GetRandomFloat(0.0, 100.0);
			}
			if(iType == 4)
			{
				fValue = GetClientTime(i) * -1.0;
			}

			if (IsClientObserver(i))
			{			
				bSpecFound = true;
				
				if (fValue > fHighestSpecValue)
				{
					fHighestSpecValue = fValue;
					iHighestSpecValueId = i;
				}
			}
		}
		
		if (fValue >= fHighestValue)
		{
			fHighestValue = fValue;
			iHighestValueId = i;
		}
	}
	
	if (bSpecFound)
	{
		return iHighestSpecValueId;
	}
	
	return iHighestValueId;
}

public void OnClientPostAdminCheck(int client)
{
	if (!g_cPluginEnabled.BoolValue)
	{
		return;
	}
	
	char sKickReason[255];

	if(GetClientCount(false) > (GetMaxHumanPlayers() - 1))
	{
		if(!GetUserAdmin(client).HasFlag(Admin_Reservation))
		{
			GetConVarString(g_cServerReason, sKickReason, sizeof(sKickReason));
			
			if(g_cRedirectEnabled.BoolValue)
			{
				//RedirectClient(iClient, g_sServerIP);
				RedirectWithDelay(client);
			}
			else
			{
				KickClient(client, "%s", sKickReason);
			}
		}
	}
}