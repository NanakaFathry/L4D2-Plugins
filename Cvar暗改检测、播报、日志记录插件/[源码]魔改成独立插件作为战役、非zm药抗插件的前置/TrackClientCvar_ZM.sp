#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define CLS_CVAR_MAXLEN 64
#define CLIENT_CHECK_INTERVAL 5.0

enum
{
	CLSA_Kick = 0,  // 踢出玩家并反馈
	CLSA_Log    	// 仅反馈
};

enum struct CLSEntry
{
	char CLSE_cvar[CLS_CVAR_MAXLEN];
	bool CLSE_hasMin;
	bool CLSE_hasMax;
	float CLSE_min;
	float CLSE_max;
	int CLSE_action;
}

ArrayList g_ClientSettingsArray = null;

Handle g_ClientSettingsCheckTimer = null;
Handle g_hCvarViolationForward = null;

ConVar g_cvEnabled = null;
ConVar g_cvDebug = null;

forward void CLS_OnCvarViolation(int client, const char[] cvar, float value, float min, float max, int action);

public Plugin myinfo = 
{
	name = "魔改版ZM-ClientSettings",
	author = "ZoneMod项目的诸位 | 魔改:Seiunsky Maomao",
	description = "魔改自ZoneMod项目中ClientSettings.sp的客户端cvar检测与反馈,将其改成独立的插件来使用.",
	version = "1.0",
	url = ""
};

/*
 * 插件提取自ZoneMod项目中的ClientSettings.sp,
 * 原项目地址：https://github.com/SirPlease/L4D2-Competitive-Rework/blob/master/addons/sourcemod/scripting/confoglcompmod/ClientSettings.sp
 * 个人只是添加内容并将其修改为独立插件来进行使用.
*/

public void OnPluginStart()
{
	g_cvEnabled = CreateConVar("sm_clientsettings_enabled", "1", "开关客户端的Cvar检测与反馈功能,1开0关.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cvDebug = CreateConVar("sm_clientsettings_debug", "0", "调试开关,1开0关.", FCVAR_NONE, true, 0.0, true, 1.0);
	
	CLSEntry clsetting;
	g_ClientSettingsArray = new ArrayList(sizeof(clsetting));

	g_hCvarViolationForward = CreateGlobalForward("CLS_OnCvarViolation", ET_Ignore, Param_Cell, Param_String, Param_Float, Param_Float, Param_Float, Param_Cell);

	RegAdminCmd("sm_clientsettings", Command_ClientSettings, ADMFLAG_CONFIG, "显示当前设置.");
	
	RegServerCmd("confogl_trackclientcvar", Command_TrackClientCvar, "添加相关Cvar设置.");
	RegServerCmd("confogl_resetclientcvars", Command_ResetTracking, "清除Cvar设置.");
	RegServerCmd("confogl_startclientchecking", Command_StartClientChecking, "开始执行.");

	//AutoExecConfig(true, "ClientSettings_ZM");	//cfg文件生成
}

public void OnConfigsExecuted()
{
	//如果启用且有跟踪的Cvar,则自动开始检查
	if (g_cvEnabled.BoolValue && g_ClientSettingsArray.Length > 0 && g_ClientSettingsCheckTimer == null)
	{
		StartTracking();
	}
}

// 检查插件是否启用
bool IsPluginEnabled()
{
	return g_cvEnabled.BoolValue;
}

// 检查调试模式是否启用
bool IsDebugEnabled()
{
	return g_cvDebug.BoolValue;
}

// 调用违规通知Forward
static void CallCvarViolationForward(int client, const char[] cvar, float value, float min, float max, int action)
{
	Call_StartForward(g_hCvarViolationForward);
	Call_PushCell(client);    // 客户端索引
	Call_PushString(cvar);    // Cvar
	Call_PushFloat(value);    // 客户端当前值
	Call_PushFloat(min);      // 最小值
	Call_PushFloat(max);      // 最大值
	Call_PushCell(action);    // 处理
	Call_Finish();
}

// 清除所有跟踪设置
static void ClearAllSettings()
{
	g_ClientSettingsArray.Clear();
}

// 定时检查客户端设置
static Action Timer_CheckClientSettings(Handle hTimer)
{
	if (!IsPluginEnabled())
	{
		if (IsDebugEnabled())
		{
			PrintToServer("[!] ClientSettings功能已停止.");
		}

		g_ClientSettingsCheckTimer = null;
		return Plugin_Stop;
	}

	EnforceAllCliSettings();
	return Plugin_Continue;
}

//对所有在线客户端执行
static void EnforceAllCliSettings()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))	//排除bot
		{
			EnforceCliSettings(i);
		}
	}
}

//对客户端执行检查
static void EnforceCliSettings(int client)
{
	int iSize = g_ClientSettingsArray.Length;
	CLSEntry clsetting;
	
	//遍历所有跟踪的cvar
	for (int i = 0; i < iSize; i++)
	{
		g_ClientSettingsArray.GetArray(i, clsetting, sizeof(clsetting));
		QueryClientConVar(client, clsetting.CLSE_cvar, QueryReply_EnforceCliSettings, i);
	}
}

//查询/反馈处理
static void QueryReply_EnforceCliSettings(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue, any value)
{
	//检查客户端是否已断开连接或正在被踢出
	if (!IsClientConnected(client) || !IsClientInGame(client) || IsClientInKickQueue(client))
	{
		return;
	}

	float fCvarVal = StringToFloat(cvarValue);
	int clsetting_index = value;

	CLSEntry clsetting;
	g_ClientSettingsArray.GetArray(clsetting_index, clsetting, sizeof(clsetting));

	//超出范围时
	if ((clsetting.CLSE_hasMin && fCvarVal < clsetting.CLSE_min) || (clsetting.CLSE_hasMax && fCvarVal > clsetting.CLSE_max))
	{
		//调用forward
		CallCvarViolationForward(client, cvarName, fCvarVal, clsetting.CLSE_min, clsetting.CLSE_max, clsetting.CLSE_action);

		//进行处理
		switch (clsetting.CLSE_action)
		{
			case CLSA_Kick:
			{
				// 构造踢出消息
				char kickMessage[256];
				Format(kickMessage, sizeof(kickMessage), "Cvar %s = %.2f 违规", cvarName, fCvarVal);

				if (clsetting.CLSE_hasMin)
				{
					Format(kickMessage, sizeof(kickMessage), "%s,最小值 %.2f", kickMessage, clsetting.CLSE_min);
				}

				if (clsetting.CLSE_hasMax)
				{
					Format(kickMessage, sizeof(kickMessage), "%s,最大值 %.2f", kickMessage, clsetting.CLSE_max);
				}

				KickClient(client, "%s", kickMessage);
			}
			case CLSA_Log:
			{
				// 仅通过forward通知，不进行其他操作
				if (IsDebugEnabled())
				{
					PrintToServer("[!] %N 的Cvar %s = %f 设置违规! [允许的数值: %f ~ %f]", client, cvarName, fCvarVal, clsetting.CLSE_min, clsetting.CLSE_max);
				}
			}
		}
	}
}

//sm_clientsettings命令处理
public Action Command_ClientSettings(int client, int args)
{
	if (client == 0)
	{
		ReplyToCommand(client, "[!] 此命令只能在游戏内使用.");
		return Plugin_Handled;
	}
	
	int iSize = g_ClientSettingsArray.Length;
	ReplyToCommand(client, "[!] 当前跟踪的客户端Cvar (总条目:%d)", iSize);

	CLSEntry clsetting;
	char message[256], shortbuf[64];
	
	for (int i = 0; i < iSize; i++)
	{
		g_ClientSettingsArray.GetArray(i, clsetting, sizeof(clsetting));
		Format(message, sizeof(message), "[!] Cvar: %s ", clsetting.CLSE_cvar);

		if (clsetting.CLSE_hasMin)
		{
			Format(shortbuf, sizeof(shortbuf), "检查最小值: %f ", clsetting.CLSE_min);
			StrCat(message, sizeof(message), shortbuf);
		}

		if (clsetting.CLSE_hasMax)
		{
			Format(shortbuf, sizeof(shortbuf), "检查最大值: %f ", clsetting.CLSE_max);
			StrCat(message, sizeof(message), shortbuf);
		}

		switch (clsetting.CLSE_action)
		{
			case CLSA_Kick:
			{
				StrCat(message, sizeof(message), "踢出并反馈");
			}
			case CLSA_Log:
			{
				StrCat(message, sizeof(message), "仅反馈");
			}
		}

		ReplyToCommand(client, message);
	}

	return Plugin_Handled;
}

//confogl_trackclientcvar处理
public Action Command_TrackClientCvar(int args)
{
	if (args < 3 || args == 4)
	{
		PrintToServer("用法: confogl_trackclientcvar <cvar> <hasMin> <min> <hasMax> <max> <action>");
		
		if (IsDebugEnabled())
		{
			char cmdbuf[128];
			GetCmdArgString(cmdbuf, sizeof(cmdbuf));
			PrintToServer("[!] 无效的指令: %s", cmdbuf);
		}
		return Plugin_Handled;
	}

	char sBuffer[CLS_CVAR_MAXLEN], cvar[CLS_CVAR_MAXLEN];
	bool hasMax = false;
	float max = 0.0;
	int action = CLSA_Kick;

	GetCmdArg(1, cvar, sizeof(cvar));

	if (!strlen(cvar))
	{
		PrintToServer("无法读取Cvar名称!");
		return Plugin_Handled;
	}

	GetCmdArg(2, sBuffer, sizeof(sBuffer));
	bool hasMin = view_as<bool>(StringToInt(sBuffer));

	GetCmdArg(3, sBuffer, sizeof(sBuffer));
	float min = StringToFloat(sBuffer);

	if (args >= 5)
	{
		GetCmdArg(4, sBuffer, sizeof(sBuffer));
		hasMax = view_as<bool>(StringToInt(sBuffer));

		GetCmdArg(5, sBuffer, sizeof(sBuffer));
		max = StringToFloat(sBuffer);
	}

	if (args >= 6)
	{
		GetCmdArg(6, sBuffer, sizeof(sBuffer));
		action = StringToInt(sBuffer);
	}

	AddClientCvar(cvar, hasMin, min, hasMax, max, action);
	PrintToServer("[!] 已添加Cvar跟踪: %s", cvar);

	return Plugin_Handled;
}

//confogl_resetclientcvars处理
public Action Command_ResetTracking(int args)
{
	if (g_ClientSettingsCheckTimer != null)
	{
		PrintToServer("[!] 检查正在进行中,无法重置!");
		return Plugin_Handled;
	}

	ClearAllSettings();
	PrintToServer("[!] 客户端Cvar跟踪信息已重置!");

	return Plugin_Handled;
}

//confogl_startclientchecking处理
public Action Command_StartClientChecking(int args)
{
	StartTracking();
	PrintToServer("[!] 客户端Cvar检查已启动!");
	return Plugin_Handled;
}

//启动定时检查
static void StartTracking()
{
	if (IsPluginEnabled() && g_ClientSettingsCheckTimer == null)
	{
		if (IsDebugEnabled())
		{
			PrintToServer("[!] 启动计时器!");
		}

		//计时器,每隔CLIENT_CHECK_INTERVAL秒检查一次
		g_ClientSettingsCheckTimer = CreateTimer(CLIENT_CHECK_INTERVAL, Timer_CheckClientSettings, _, TIMER_REPEAT);
	}
	else
	{
		PrintToServer("[!] 跟踪已启动!");
	}
}

//添加Cvar到跟踪列表
static void AddClientCvar(const char[] cvar, bool hasMin, float min, bool hasMax, float max, int action)
{
	// 检查是否正在检查中
	if (g_ClientSettingsCheckTimer != null)
	{
		PrintToServer("[!] 检查正在进行中,无法添加新的Cvar跟踪");

		if (IsDebugEnabled())
		{
			PrintToServer("[!] 不要在检查过程中添加新的Cvar%s!", cvar);
		}
		return;
	}

	// 验证参数
	if (!(hasMin || hasMax))
	{
		PrintToServer("[!] Cvar %s 请设置是否要进行最小值和最大值的检查!", cvar);
		return;
	}

	if (max < min)
	{
		PrintToServer("[!] Cvar %s 的最大值不能够小于最小值! (%f < %f)", cvar, max, min);
		return;
	}

	if (strlen(cvar) >= CLS_CVAR_MAXLEN)
	{
		PrintToServer("[!] Cvar名称 %s 超过最大长度限制! (%d)", cvar, CLS_CVAR_MAXLEN);
		return;
	}

	//是否存在相同的Cvar
	int iSize = g_ClientSettingsArray.Length;
	CLSEntry newEntry;

	for (int i = 0; i < iSize; i++)
	{
		g_ClientSettingsArray.GetArray(i, newEntry, sizeof(newEntry));
		if (strcmp(newEntry.CLSE_cvar, cvar, false) == 0)
		{
			PrintToServer("[!] Cvar %s 已被添加过了!", cvar);
			return;
		}
	}

	// 设置新的跟踪条目cvar
	newEntry.CLSE_hasMin = hasMin;
	newEntry.CLSE_min = min;
	newEntry.CLSE_hasMax = hasMax;
	newEntry.CLSE_max = max;
	newEntry.CLSE_action = action;
	strcopy(newEntry.CLSE_cvar, CLS_CVAR_MAXLEN, cvar);

	// 调试日志
	if (IsDebugEnabled())
	{
		PrintToServer("[!] 跟踪Cvar:%s 检查最小值:%d 允许的最小值:%f 检查最大值:%d 允许的最大值:%f 处理:%d", cvar, hasMin, min, hasMax, max, action);
	}

	// 添加到跟踪列表
	g_ClientSettingsArray.PushArray(newEntry, sizeof(newEntry));
}