#pragma semicolon 1

#define PLUGIN_AUTHOR "RumbleFrog, SourceBans++ Dev Team"
#define PLUGIN_VERSION "1.2.0"

#include <sourcemod>
#include <sourcebanspp>
#include <sourcecomms>
#include <SteamWorks>
#include <smjansson>

#pragma newdecls required

enum
{
	Ban,
	Report,
	Comms,
	Type_Count,
	Type_Unknown,
};

int EmbedColors[Type_Count] = {
	0xDA1D87, // Ban
	0xF9D942, // Report
	0x4362FA, // Comms
};

ConVar Convars[Type_Count],
	Username,
	ProfilePictureURL,
	WebsiteBaseURL,
	DiscordRoleID;

char sEndpoints[Type_Count][256]
	, sHostname[64]
	, sHost[64]
	, sDiscordRoleID[32];

public Plugin myinfo =
{
	name = "SourceBans++ Discord Plugin",
	author = PLUGIN_AUTHOR,
	description = "Listens for ban & report forward and sends it to webhook endpoints",
	version = PLUGIN_VERSION,
	url = "https://sbpp.github.io"
};

public void OnPluginStart()
{
	CreateConVar("sbpp_discord_version", PLUGIN_VERSION, "SBPP Discord Version.", FCVAR_REPLICATED | FCVAR_SPONLY | FCVAR_DONTRECORD | FCVAR_NOTIFY);

	Convars[Ban] = CreateConVar("sbpp_discord_banhook", "", "Discord web hook endpoint for ban forward. Leave empty to disable.", FCVAR_PROTECTED);
	
	Convars[Report] = CreateConVar("sbpp_discord_reporthook", "", "Discord web hook endpoint for report forward. Leave empty to disable.", FCVAR_PROTECTED);
	
	Convars[Comms] = CreateConVar("sbpp_discord_commshook", "", "Discord web hook endpoint for comms forward. Leave empty to disable.", FCVAR_PROTECTED);

	WebsiteBaseURL = CreateConVar("sbpp_website_url", "", "The base url of your website. Leave empty to disable.");

	Username = CreateConVar("sbpp_discord_username", "Sourcebans++", "The username of the webhook.");

	ProfilePictureURL = CreateConVar("sbpp_discord_pp_url", "https://sbpp.github.io/img/favicons/android-chrome-512x512.png", "A URL pointing to the profile picture for the webhook.");

	DiscordRoleID = CreateConVar("sbpp_discord_roleid", "", "The Discord role id that you would like mentioned when receiving a report. Leave empty to disable.");

	AutoExecConfig(true,"sbpp_discord");

	Convars[Ban].AddChangeHook(OnConvarChanged);
	Convars[Report].AddChangeHook(OnConvarChanged);
	Convars[Comms].AddChangeHook(OnConvarChanged);
	DiscordRoleID.AddChangeHook(OnConvarChanged);
}

public void OnConfigsExecuted()
{
	FindConVar("hostname").GetString(sHostname, sizeof sHostname);
	
	int ip[4];
	
	SteamWorks_GetPublicIP(ip);
	
	if (SteamWorks_GetPublicIP(ip))
	{
		Format(sHost, sizeof sHost, "%d.%d.%d.%d:%d", ip[0], ip[1], ip[2], ip[3], FindConVar("hostport").IntValue);
	} else
	{
		int iIPB = FindConVar("hostip").IntValue;
		Format(sHost, sizeof sHost, "%d.%d.%d.%d:%d", iIPB >> 24 & 0x000000FF, iIPB >> 16 & 0x000000FF, iIPB >> 8 & 0x000000FF, iIPB & 0x000000FF, FindConVar("hostport").IntValue);
	}
	
	Convars[Ban].GetString(sEndpoints[Ban], sizeof sEndpoints[]);
	Convars[Report].GetString(sEndpoints[Report], sizeof sEndpoints[]);
	Convars[Comms].GetString(sEndpoints[Comms], sizeof sEndpoints[]);
	DiscordRoleID.GetString(sDiscordRoleID, sizeof sDiscordRoleID);
}

public void SBPP_OnBanPlayer(int iAdmin, int iTarget, int iTime, const char[] sReason)
{
	if (!StrEqual(sEndpoints[Ban], ""))
		SendReport(iAdmin, iTarget, sReason, Ban, iTime);
}

public void SourceComms_OnBlockAdded(int iAdmin, int iTarget, int iTime, int iCommType, char[] sReason)
{
	if (!StrEqual(sEndpoints[Comms], ""))
		SendReport(iAdmin, iTarget, sReason, Comms, iTime, iCommType);
}

public void SBPP_OnReportPlayer(int iReporter, int iTarget, const char[] sReason)
{
	if (!StrEqual(sEndpoints[Report], ""))
		SendReport(iReporter, iTarget, sReason, Report);
}

void SendReport(int iClient, int iTarget, const char[] sReason, int iType = Ban, int iTime = -1, any extra = 0)
{
	if (iTarget != -1 && !IsValidClient(iTarget))
		return;

	char sAuthor[MAX_NAME_LENGTH], 
		sTarget[MAX_NAME_LENGTH], 
		sAuthorID[32], 
		sTargetID64[32], 
		sTargetID[32], 
		sJson[2048], 
		sBuffer[256],
		szUsername[128],
		szProfilePictureURL[256];

	GetConVarString(ProfilePictureURL, szProfilePictureURL, sizeof szProfilePictureURL);
	GetConVarString(Username, szUsername, sizeof szUsername);

	if (IsValidClient(iClient))
	{
		GetClientName(iClient, sAuthor, sizeof sAuthor);
		GetClientAuthId(iClient, AuthId_Steam2, sAuthorID, sizeof sAuthorID);
	} else
	{
		Format(sAuthor, sizeof sAuthor, "Console");
		Format(sAuthorID, sizeof sAuthorID, "N/A");
	}

	GetClientAuthId(iTarget, AuthId_SteamID64, sTargetID64, sizeof sTargetID64);
	GetClientName(iTarget, sTarget, sizeof sTarget);
	GetClientAuthId(iTarget, AuthId_Steam2, sTargetID, sizeof sTargetID);

	Handle jRequest = json_object();

	Handle jEmbeds = json_array();


	Handle jContent = json_object();
	
	json_object_set(jContent, "color", json_integer(GetEmbedColor(iType)));

	char szURLBuffer[512];
	GetConVarString(WebsiteBaseURL, szURLBuffer, sizeof(szURLBuffer));

	if (iType == Report && !StrEqual(sDiscordRoleID, ""))
	{
		Format(sBuffer, sizeof sBuffer, "<@&%s>", sDiscordRoleID);
		json_object_set_new(jRequest, "content", json_string(sBuffer));
	}

	if(!(StrEqual(szURLBuffer, "")))
	{
		json_object_set(jContent, "title", json_string("View on Sourcebans"));
	
		if(iType == Comms)
			Format(sBuffer, sizeof sBuffer, "%s/index.php?p=commslist&searchText=%s", szURLBuffer, sTargetID);
		else if (iType == Ban)
			Format(sBuffer, sizeof sBuffer, "%s/index.php?p=banlist&searchText=%s", szURLBuffer, sTargetID);
		else if (iType == Report)
			Format(sBuffer, sizeof sBuffer, "%s/index.php?p=admin&c=bans#^2", szURLBuffer);
		json_object_set(jContent, "url", json_string(sBuffer));
	}

	Handle jContentAuthor = json_object();

	json_object_set_new(jContentAuthor, "name", json_string(sTarget));
	Format(sBuffer, sizeof sBuffer, "https://steamcommunity.com/profiles/%s", sTargetID64);
	json_object_set_new(jContentAuthor, "url", json_string(sBuffer));
	json_object_set_new(jContentAuthor, "icon_url", json_string(szProfilePictureURL));
	json_object_set_new(jContent, "author", jContentAuthor);

	Handle jContentFooter = json_object();

	Format(sBuffer, sizeof sBuffer, "%s (%s)", sHostname, sHost);
	json_object_set_new(jContentFooter, "text", json_string(sBuffer));
	json_object_set_new(jContentFooter, "icon_url", json_string(szProfilePictureURL));
	json_object_set_new(jContent, "footer", jContentFooter);


	Handle jFields = json_array();


	Handle jFieldAuthor = json_object();
	json_object_set_new(jFieldAuthor, "name", json_string("Author"));
	Format(sBuffer, sizeof sBuffer, "%s (%s)", sAuthor, sAuthorID);
	json_object_set_new(jFieldAuthor, "value", json_string(sBuffer));
	json_object_set_new(jFieldAuthor, "inline", json_boolean(true));

	Handle jFieldTarget = json_object();
	json_object_set_new(jFieldTarget, "name", json_string("Target"));
	Format(sBuffer, sizeof sBuffer, "%s (%s)", sTarget, sTargetID);
	json_object_set_new(jFieldTarget, "value", json_string(sBuffer));
	json_object_set_new(jFieldTarget, "inline", json_boolean(true));

	Handle jFieldReason = json_object();
	json_object_set_new(jFieldReason, "name", json_string("Reason"));
	json_object_set_new(jFieldReason, "value", json_string(sReason));

	json_array_append_new(jFields, jFieldAuthor);
	json_array_append_new(jFields, jFieldTarget);

	if (iType == Ban || iType == Comms)
	{
		Handle jFieldDuration = json_object();

		json_object_set_new(jFieldDuration, "name", json_string("Duration"));

		if (iTime > 0)
			Format(sBuffer, sizeof sBuffer, "%d Minutes", iTime);
		else if (iTime < 0)
			Format(sBuffer, sizeof sBuffer, "Session");
		else
			Format(sBuffer, sizeof sBuffer, "Permanent");

		json_object_set_new(jFieldDuration, "value", json_string(sBuffer));

		json_array_append_new(jFields, jFieldDuration);
	}
	
	if (iType == Comms)
	{
		Handle jFieldCommType = json_object();
		
		json_object_set_new(jFieldCommType, "name", json_string("Comm Type"));
		
		char cType[32];
		
		GetCommType(cType, sizeof cType, extra);
		
		json_object_set_new(jFieldCommType, "value", json_string(cType));
		
		json_array_append_new(jFields, jFieldCommType);
	}

	json_array_append_new(jFields, jFieldReason);


	json_object_set_new(jContent, "fields", jFields);


	json_array_append_new(jEmbeds, jContent);

	json_object_set_new(jRequest, "username", json_string(szUsername));
	json_object_set_new(jRequest, "avatar_url", json_string(szProfilePictureURL));
	json_object_set_new(jRequest, "embeds", jEmbeds);


	json_dump(jRequest, sJson, sizeof sJson, 0, false, false, true);

	#if defined DEBUG
		PrintToServer(sJson);
	#endif

	CloseHandle(jRequest);
	
	char sEndpoint[256];
	
	GetEndpoint(sEndpoint, sizeof sEndpoint, iType);

	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, sEndpoint);

	SteamWorks_SetHTTPRequestContextValue(hRequest, iClient, iTarget);
	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "payload_json", sJson);
	SteamWorks_SetHTTPCallbacks(hRequest, OnHTTPRequestComplete);

	if (!SteamWorks_SendHTTPRequest(hRequest))
		LogError("HTTP request failed for %s against %s", sAuthor, sTarget);
}

public int OnHTTPRequestComplete(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, int iClient, int iTarget)
{
	if (!bRequestSuccessful || eStatusCode != k_EHTTPStatusCode204NoContent)
	{
		LogError("HTTP request failed for %N against %N", iClient, iTarget);

		#if defined DEBUG
			int iSize;

			SteamWorks_GetHTTPResponseBodySize(hRequest, iSize);

			char[] sBody = new char[iSize];

			SteamWorks_GetHTTPResponseBodyData(hRequest, sBody, iSize);

			PrintToServer(sBody);
			PrintToServer("Status Code: %d", eStatusCode);
			PrintToServer("SteamWorks_IsLoaded: %d", SteamWorks_IsLoaded());
		#endif
	}

	CloseHandle(hRequest);
}

public void OnConvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (convar == Convars[Ban])
		Convars[Ban].GetString(sEndpoints[Ban], sizeof sEndpoints[]);
	else if (convar == Convars[Report])
		Convars[Report].GetString(sEndpoints[Report], sizeof sEndpoints[]);
	else if (convar == Convars[Comms])
		Convars[Comms].GetString(sEndpoints[Comms], sizeof sEndpoints[]);
	else if (convar == DiscordRoleID)
		DiscordRoleID.GetString(sDiscordRoleID, sizeof sDiscordRoleID);
}

int GetEmbedColor(int iType)
{
	if (iType != Type_Unknown)
		return EmbedColors[iType];
	
	return EmbedColors[Ban];
}

void GetEndpoint(char[] sBuffer, int iBufferSize, int iType)
{
	if (!StrEqual(sEndpoints[iType], ""))
	{
		strcopy(sBuffer, iBufferSize, sEndpoints[iType]);
		return;
	}
	strcopy(sBuffer, iBufferSize, "");
}

void GetCommType(char[] sBuffer, int iBufferSize, int iType)
{
	switch (iType)
	{
		case TYPE_MUTE:
			strcopy(sBuffer, iBufferSize, "Mute");
		case TYPE_GAG:
			strcopy(sBuffer, iBufferSize, "Gag");
		case TYPE_SILENCE:
			strcopy(sBuffer, iBufferSize, "Silence");
	}
}

stock bool IsValidClient(int iClient, bool bAlive = false)
{
	if (iClient >= 1 &&
	iClient <= MaxClients &&
	IsClientConnected(iClient) &&
	IsClientInGame(iClient) &&
	!IsFakeClient(iClient) &&
	(bAlive == false || IsPlayerAlive(iClient)))
	{
		return true;
	}

	return false;
}
