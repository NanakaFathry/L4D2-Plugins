#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <left4dhooks>
#include <l4d2util>
#include <colors>

Handle
	g_hCookie,
	g_hDamageTimer[MAXPLAYERS + 1],
	g_hBeamTimer1[MAXPLAYERS + 1],
	g_hBeamTimer2[MAXPLAYERS + 1];

float
	g_fPoint1[MAXPLAYERS + 1][3],
	g_fPoint2[MAXPLAYERS + 1][3],
	g_fDamageCache[MAXPLAYERS + 1][MAXPLAYERS + 1],
	g_fFlowDistanceA[MAXPLAYERS + 1],
	g_fFlowDistanceB[MAXPLAYERS + 1],
	g_fFlowDistanceC[MAXPLAYERS + 1],
	g_fFlowDistanceD[MAXPLAYERS + 1];

bool
	g_bPluginEnabled,
	g_bPluginDmg,
	g_bPluginSIHighLight,
	g_bPoint1Set[MAXPLAYERS + 1],
	g_bPoint2Set[MAXPLAYERS + 1],
	g_bDamageActive[MAXPLAYERS + 1],
	g_bLeftSafeArea[MAXPLAYERS + 1],
	g_bRoundEndExecuted;

int
	g_iWitchModel1[MAXPLAYERS + 1],
	g_iWitchModel2[MAXPLAYERS + 1],
	g_iBeamSprite;

ConVar
	g_cvPluginEnabled,
	g_cvPluginDmg,
	g_cvPluginSIHighLight;

ArrayList
	g_aSpawnedSI[MAXPLAYERS + 1];

public Plugin myinfo = 
{
	name = "星云猫猫标记测距",
	author = "Seiunsky Maomao",
	description = "自用的测距插件, 功能是标记脚下两点坐标, 并计算距离, 以及特感的冻结、生成功能.",
	version = "1.5.1",
	url = "https://github.com/NanakaFathry/L4D2-Plugins"
};

public void OnPluginStart()
{
	g_cvPluginEnabled = CreateConVar("bjkg", "1", "插件开关 [1 → 开启 | 0 → 关闭]", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cvPluginDmg = CreateConVar("bj_dmg", "0", "显示造成的伤害 [1 → 显示 | 0 → 不显示]", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cvPluginSIHighLight = CreateConVar("bj_sihl", "0", "显示特感高亮光圈 [1 → 显示 | 0 → 不显示]", FCVAR_NONE, true, 0.0, true, 1.0);

	RegAdminCmd("sm_bj1", Command_MarkPoint1, ADMFLAG_ROOT, "标记、取消坐标点1");
	RegAdminCmd("sm_biaoji1", Command_MarkPoint1, ADMFLAG_ROOT, "标记、取消坐标点1");
	RegAdminCmd("sm_bj2", Command_MarkPoint2, ADMFLAG_ROOT, "标记、取消坐标点2");
	RegAdminCmd("sm_biaoji2", Command_MarkPoint2, ADMFLAG_ROOT, "标记、取消坐标点2");
	RegAdminCmd("sm_bj", Command_ToggleMenu, ADMFLAG_ROOT, "打开坐标传送栏等");
	RegAdminCmd("sm_biaoji", Command_ToggleMenu, ADMFLAG_ROOT, "打开坐标传送栏等");
	RegAdminCmd("sm_si", Command_SpawnSI, ADMFLAG_ROOT, "打开特感生成表");
	RegAdminCmd("sm_bjcur", Command_ShowFlowPercentage, ADMFLAG_ROOT, "显示当前玩家所处位置信息");
	
	g_bPluginEnabled = GetConVarBool(g_cvPluginEnabled);
	g_bPluginDmg = GetConVarBool(g_cvPluginDmg);
	g_bPluginSIHighLight = GetConVarBool(g_cvPluginSIHighLight);
	
	g_hCookie = RegClientCookie("biaoji_points", "存储标记点", CookieAccess_Private);

	HookConVarChange(g_cvPluginEnabled, OnConVarChanged);
	HookConVarChange(g_cvPluginDmg, OnConVarChanged);
	HookConVarChange(g_cvPluginSIHighLight, OnConVarChanged);

	//检查客户端cookie是否已缓存
	for (int i = 1; i <= MaxClients; i++)
	{
		if (AreClientCookiesCached(i))
		{
			OnClientCookiesCached(i);
		}
	}

	//初始化特殊感染者存储数组
	for (int i = 1; i <= MaxClients; i++)
	{
		g_aSpawnedSI[i] = new ArrayList();
	}

	AutoExecConfig(true, "Biaoji");
}

//ConVar变化回调
public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (convar == g_cvPluginEnabled)
	{
		g_bPluginEnabled = g_cvPluginEnabled.BoolValue;
	}
	if (convar == g_cvPluginDmg)
	{
		g_bPluginDmg = g_cvPluginDmg.BoolValue;
	}
	if (convar == g_cvPluginSIHighLight)
	{
		g_bPluginSIHighLight = g_cvPluginSIHighLight.BoolValue;
	}
}

//预加载与清理工作
public void OnMapStart()
{
	g_iBeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt");

	for (int client = 1; client <= MaxClients; client++)
	{
		CleanUpSomething(client);
	}
}

//读取标记点
public void OnClientCookiesCached(int client)
{
	if (!g_bPluginEnabled)
	{
		return;
	}

	//读取客户端 Cookie 中的标记点数据
	char sCookieValue[256];
	GetClientCookie(client, g_hCookie, sCookieValue, sizeof(sCookieValue));

	if (strlen(sCookieValue) > 0)
	{
		char sPoints[2][64];
		ExplodeString(sCookieValue, "|", sPoints, 2, 64);

		if (StrContains(sPoints[0], ",") != -1)
		{
			StringToVector(sPoints[0], g_fPoint1[client]);
			g_bPoint1Set[client] = true;
			CreateWitchModel(client, 1); // 创建第一个点
		}

		if (StrContains(sPoints[1], ",") != -1)
		{
			StringToVector(sPoints[1], g_fPoint2[client]);
			g_bPoint2Set[client] = true;
			CreateWitchModel(client, 2); // 创建第二个点
		}
	}
}

//标记点1
Action Command_MarkPoint1(int client, int args)
{
	if (!g_bPluginEnabled)
	{
		CPrintToChat(client, "{default}插件功能{green}已关闭{default}.");
		CPrintToChat(client, "{default}请使用 {green}!cvar bjkg 1 {default}打开插件开关.");
		return Plugin_Handled;
	}

	//直接赋予返回值
	g_bLeftSafeArea[client] = L4D_IsInFirstCheckpoint(client);

	if (g_bPoint1Set[client])
	{
		//取消第一个点
		g_bPoint1Set[client] = false;
		CPrintToChat(client, "{lightgreen}取消{green}坐标点1{default}.");
		RemoveWitchModel(client, 1); // 移除第一个点
	}
	else
	{
		//标记第一个点
		GetClientAbsOrigin(client, g_fPoint1[client]);
		g_bPoint1Set[client] = true;
		
		CPrintToChat(client, " ");
		CPrintToChat(client, "{default}坐标点1: ({lightgreen}%.2f{default}, {lightgreen}%.2f{default}, {lightgreen}%.2f{default})", g_fPoint1[client][0], g_fPoint1[client][1], g_fPoint1[client][2]);

		//点1流程距离
		g_fFlowDistanceA[client] = GetFlowFromPoint(g_fPoint1[client]);
		//g_fFlowDistanceA[client] = GetFlowFromPlayerPoint(client);

		if ((g_fFlowDistanceA[client] != -9999.0) && (!g_bLeftSafeArea[client]))
		{
			CPrintToChat(client, "{default}坐标点1流程为: {lightgreen}%.2f", g_fFlowDistanceA[client]);
		}
		else if(g_fFlowDistanceA[client] == -9999.0 && (!g_bLeftSafeArea[client]))
		{
			g_fFlowDistanceB[client] = GetFlowFromLastPlayerArea1(client);
			if (g_fFlowDistanceB[client] != -9999.0)
			{
				CPrintToChat(client, "{default}坐标点1流程约为: {green}%.2f", g_fFlowDistanceB[client]);
			}
		}
		if (g_fFlowDistanceA[client] != -9999.0 && g_bLeftSafeArea[client])
		{
			CPrintToChat(client, "{default}坐标点1流程为: {lightgreen}%.2f", g_fFlowDistanceA[client]);
		}
		else if(g_fFlowDistanceA[client] == -9999.0 && g_bLeftSafeArea[client])
		{
			g_fFlowDistanceB[client] = GetFlowFromLastPlayerArea1(client);
			if (g_fFlowDistanceB[client] != -9999.0)
			{
				CPrintToChat(client, "{default}坐标点1流程约为: {green}%.2f", g_fFlowDistanceB[client]);
			}
		}
		CreateWitchModel(client, 1); // 创建第一个点

		//如果两个点都已标记，计算距离和流程间距
		if (g_bPoint1Set[client] && g_bPoint2Set[client])
		{
			float distance = CalculateDistance(g_fPoint1[client], g_fPoint2[client]);
			CPrintToChat(client, "{default}两点间直线距离为: {lightgreen}%.2f", distance);

			//在安全屋内
			//两个点都取值正常,则不需要使用大约值
			if ((g_fFlowDistanceA[client] != -9999.0) && (g_fFlowDistanceC[client] != -9999.0) && (!g_bLeftSafeArea[client]))
			{
				float g_fFlowDistanceDiff1 = FloatAbs(g_fFlowDistanceA[client] - g_fFlowDistanceC[client]);
				CPrintToChat(client, "{default}两点间流程间距为: {lightgreen}%.2f", g_fFlowDistanceDiff1);
			}
			//点1取值正常点2不正常,则使用大约值
			if ((g_fFlowDistanceA[client] != -9999.0) && (g_fFlowDistanceC[client] == -9999.0) && (g_fFlowDistanceD[client] != -9999.0) && (!g_bLeftSafeArea[client]))
			{
				float g_fFlowDistanceDiff1 = FloatAbs(g_fFlowDistanceA[client] - g_fFlowDistanceD[client]);
				CPrintToChat(client, "{default}两点间流程间距约为: {lightgreen}%.2f", g_fFlowDistanceDiff1);
			}
			//点1取值不正常点2正常,则使用大约值
			if ((g_fFlowDistanceA[client] == -9999.0) && (g_fFlowDistanceC[client] != -9999.0) && (g_fFlowDistanceB[client] != -9999.0) && (!g_bLeftSafeArea[client]))
			{
				float g_fFlowDistanceDiff1 = FloatAbs(g_fFlowDistanceB[client] - g_fFlowDistanceC[client]);
				CPrintToChat(client, "{default}两点间流程间距约为: {lightgreen}%.2f", g_fFlowDistanceDiff1);
			}
			//点1点2取值都不正常,则使用大约值
			if ((g_fFlowDistanceA[client] == -9999.0) && (g_fFlowDistanceC[client] == -9999.0) && (g_fFlowDistanceB[client] != -9999.0) && (g_fFlowDistanceD[client] != -9999.0) && (!g_bLeftSafeArea[client]))
			{
				float g_fFlowDistanceDiff1 = FloatAbs(g_fFlowDistanceB[client] - g_fFlowDistanceD[client]);
				CPrintToChat(client, "{default}两点间流程间距约为: {lightgreen}%.2f", g_fFlowDistanceDiff1);
			}
			//在安全屋外
			//两个点都取值正常,则不需要使用大约值
			if ((g_fFlowDistanceA[client] != -9999.0) && (g_fFlowDistanceC[client] != -9999.0) && g_bLeftSafeArea[client])
			{
				float g_fFlowDistanceDiff1 = FloatAbs(g_fFlowDistanceA[client] - g_fFlowDistanceC[client]);
				CPrintToChat(client, "{default}两点间流程间距为: {lightgreen}%.2f", g_fFlowDistanceDiff1);
			}
			//点1取值正常点2不正常,则使用大约值
			if ((g_fFlowDistanceA[client] != -9999.0) && (g_fFlowDistanceC[client] == -9999.0) && (g_fFlowDistanceD[client] != -9999.0) && g_bLeftSafeArea[client])
			{
				float g_fFlowDistanceDiff1 = FloatAbs(g_fFlowDistanceA[client] - g_fFlowDistanceD[client]);
				CPrintToChat(client, "{default}两点间流程间距约为: {lightgreen}%.2f", g_fFlowDistanceDiff1);
			}
			//点1取值不正常点2正常,则使用大约值
			if ((g_fFlowDistanceA[client] == -9999.0) && (g_fFlowDistanceC[client] != -9999.0) && (g_fFlowDistanceB[client] != -9999.0) && g_bLeftSafeArea[client])
			{
				float g_fFlowDistanceDiff1 = FloatAbs(g_fFlowDistanceB[client] - g_fFlowDistanceC[client]);
				CPrintToChat(client, "{default}两点间流程间距约为: {lightgreen}%.2f", g_fFlowDistanceDiff1);
			}
			//点1点2取值都不正常,则使用大约值
			if ((g_fFlowDistanceA[client] == -9999.0) && (g_fFlowDistanceC[client] == -9999.0) && (g_fFlowDistanceB[client] != -9999.0) && (g_fFlowDistanceD[client] != -9999.0) && g_bLeftSafeArea[client])
			{
				float g_fFlowDistanceDiff1 = FloatAbs(g_fFlowDistanceB[client] - g_fFlowDistanceD[client]);
				CPrintToChat(client, "{default}两点间流程间距约为: {lightgreen}%.2f", g_fFlowDistanceDiff1);
			}
		}
	}

	SavePoints(client); //保存标记点
	return Plugin_Handled;
}

//标记点2
Action Command_MarkPoint2(int client, int args)
{
	if (!g_bPluginEnabled)
	{
		CPrintToChat(client, "{default}插件功能{green}已关闭{default}.");
		CPrintToChat(client, "{default}请使用 {green}!cvar bjkg 1 {default}打开插件开关.");
		return Plugin_Handled;
	}

	//直接赋予返回值
	g_bLeftSafeArea[client] = L4D_IsInFirstCheckpoint(client);

	if (g_bPoint2Set[client])
	{
		// 取消第二个点
		g_bPoint2Set[client] = false;
		CPrintToChat(client, "{lightgreen}取消{green}坐标点2{default}.");
		RemoveWitchModel(client, 2); //移除第二个点
	}
	else
	{
		// 标记第二个点
		GetClientAbsOrigin(client, g_fPoint2[client]);
		g_bPoint2Set[client] = true;
		
		CPrintToChat(client, " ");
		CPrintToChat(client, "{default}坐标点2: ({lightgreen}%.2f{default}, {lightgreen}%.2f{default}, {lightgreen}%.2f{default})", g_fPoint2[client][0], g_fPoint2[client][1], g_fPoint2[client][2]);

		//点2流程距离
		g_fFlowDistanceC[client] = GetFlowFromPoint(g_fPoint2[client]);
		//g_fFlowDistanceC[client] = GetFlowFromPlayerPoint(client);

		if ((g_fFlowDistanceC[client] != -9999.0) && (!g_bLeftSafeArea[client]))
		{
			CPrintToChat(client, "{default}坐标点2流程为: {lightgreen}%.2f", g_fFlowDistanceC[client]);
		}
		else if(g_fFlowDistanceC[client] == -9999.0 && (!g_bLeftSafeArea[client]))
		{
			g_fFlowDistanceD[client] = GetFlowFromLastPlayerArea1(client);
			if (g_fFlowDistanceD[client] != -9999.0)
			{
				CPrintToChat(client, "{default}坐标点2流程约为: {green}%.2f", g_fFlowDistanceD[client]);
			}
		}
		if (g_fFlowDistanceC[client] != -9999.0 && g_bLeftSafeArea[client])
		{
			CPrintToChat(client, "{default}坐标点2流程为: {lightgreen}%.2f", g_fFlowDistanceC[client]);
		}
		else if(g_fFlowDistanceC[client] == -9999.0 && g_bLeftSafeArea[client])
		{
			g_fFlowDistanceD[client] = GetFlowFromLastPlayerArea1(client);
			if (g_fFlowDistanceD[client] != -9999.0)
			{
				CPrintToChat(client, "{default}坐标点2流程约为: {green}%.2f", g_fFlowDistanceD[client]);
			}
		}
		CreateWitchModel(client, 2);	//创建第二个点

		if (g_bPoint1Set[client] && g_bPoint2Set[client])
		{
			float distance = CalculateDistance(g_fPoint1[client], g_fPoint2[client]);
			CPrintToChat(client, "{default}两点间直线距离为: {lightgreen}%.2f", distance);

			//在安全屋内
			//两个点都取值正常,则不需要使用大约值
			if ((g_fFlowDistanceA[client] != -9999.0) && (g_fFlowDistanceC[client] != -9999.0) && (!g_bLeftSafeArea[client]))
			{
				float g_fFlowDistanceDiff2 = FloatAbs(g_fFlowDistanceA[client] - g_fFlowDistanceC[client]);
				CPrintToChat(client, "{default}两点间流程间距为: {lightgreen}%.2f", g_fFlowDistanceDiff2);
			}
			//点1取值正常点2不正常,则使用大约值
			if ((g_fFlowDistanceA[client] != -9999.0) && (g_fFlowDistanceC[client] == -9999.0) && (g_fFlowDistanceD[client] != -9999.0) && (!g_bLeftSafeArea[client]))
			{
				float g_fFlowDistanceDiff2 = FloatAbs(g_fFlowDistanceA[client] - g_fFlowDistanceD[client]);
				CPrintToChat(client, "{default}两点间流程间距约为: {lightgreen}%.2f", g_fFlowDistanceDiff2);
			}
			//点1取值不正常点2正常,则使用大约值
			if ((g_fFlowDistanceA[client] == -9999.0) && (g_fFlowDistanceC[client] != -9999.0) && (g_fFlowDistanceB[client] != -9999.0) && (!g_bLeftSafeArea[client]))
			{
				float g_fFlowDistanceDiff2 = FloatAbs(g_fFlowDistanceB[client] - g_fFlowDistanceC[client]);
				CPrintToChat(client, "{default}两点间流程间距约为: {lightgreen}%.2f", g_fFlowDistanceDiff2);
			}
			//点1点2取值都不正常,则使用大约值
			if ((g_fFlowDistanceA[client] == -9999.0) && (g_fFlowDistanceC[client] == -9999.0) && (g_fFlowDistanceB[client] != -9999.0) && (g_fFlowDistanceD[client] != -9999.0) && (!g_bLeftSafeArea[client]))
			{
				float g_fFlowDistanceDiff2 = FloatAbs(g_fFlowDistanceB[client] - g_fFlowDistanceD[client]);
				CPrintToChat(client, "{default}两点间流程间距约为: {lightgreen}%.2f", g_fFlowDistanceDiff2);
			}
			//在安全屋外
			//两个点都取值正常,则不需要使用大约值
			if ((g_fFlowDistanceA[client] != -9999.0) && (g_fFlowDistanceC[client] != -9999.0) && g_bLeftSafeArea[client])
			{
				float g_fFlowDistanceDiff2 = FloatAbs(g_fFlowDistanceA[client] - g_fFlowDistanceC[client]);
				CPrintToChat(client, "{default}两点间流程间距为: {lightgreen}%.2f", g_fFlowDistanceDiff2);
			}
			//点1取值正常点2不正常,则使用大约值
			if ((g_fFlowDistanceA[client] != -9999.0) && (g_fFlowDistanceC[client] == -9999.0) && (g_fFlowDistanceD[client] != -9999.0) && g_bLeftSafeArea[client])
			{
				float g_fFlowDistanceDiff2 = FloatAbs(g_fFlowDistanceA[client] - g_fFlowDistanceD[client]);
				CPrintToChat(client, "{default}两点间流程间距约为: {lightgreen}%.2f", g_fFlowDistanceDiff2);
			}
			//点1取值不正常点2正常,则使用大约值
			if ((g_fFlowDistanceA[client] == -9999.0) && (g_fFlowDistanceC[client] != -9999.0) && (g_fFlowDistanceB[client] != -9999.0) && g_bLeftSafeArea[client])
			{
				float g_fFlowDistanceDiff2 = FloatAbs(g_fFlowDistanceB[client] - g_fFlowDistanceC[client]);
				CPrintToChat(client, "{default}两点间流程间距约为: {lightgreen}%.2f", g_fFlowDistanceDiff2);
			}
			//点1点2取值都不正常,则使用大约值
			if ((g_fFlowDistanceA[client] == -9999.0) && (g_fFlowDistanceC[client] == -9999.0) && (g_fFlowDistanceB[client] != -9999.0) && (g_fFlowDistanceD[client] != -9999.0) && g_bLeftSafeArea[client])
			{
				float g_fFlowDistanceDiff2 = FloatAbs(g_fFlowDistanceB[client] - g_fFlowDistanceD[client]);
				CPrintToChat(client, "{default}两点间流程间距约为: {lightgreen}%.2f", g_fFlowDistanceDiff2);
			}
		}
	}

	SavePoints(client); //保存点
	return Plugin_Handled;
}

//左侧栏菜单命令
Action Command_ToggleMenu(int client, int args)
{
	if (!g_bPluginEnabled)
	{
		CPrintToChat(client, "{default}插件功能{green}已关闭{default}.");
		CPrintToChat(client, "{default}请使用 {green}!cvar bjkg 1 {default}打开插件开关.");
		return Plugin_Handled;
	}

	ShowPointsMenu(client);
	return Plugin_Handled;
}

//左侧栏菜单
void ShowPointsMenu(int client)
{
	Menu menu = new Menu(PointsMenuHandler);
	menu.SetTitle("坐标点传送/信息:");
	
	//穿墙
	MoveType movetype = GetEntityMoveType(client);
	if (movetype != MOVETYPE_NOCLIP)
	{
		menu.AddItem("noclip", "开启穿墙");
	}
	else
	{
		menu.AddItem("noclip", "关闭穿墙");
	}

	//坐标点
	if (g_bPoint1Set[client])
	{
		menu.AddItem("point1", "传送到坐标点1");
		menu.AddItem("delete_point1", "删除坐标点1");
	}
	else
	{
		menu.AddItem("add_point1", "添加坐标点1");
	}

	if (g_bPoint2Set[client])
	{
		menu.AddItem("point2", "传送到坐标点2");
		menu.AddItem("delete_point2", "删除坐标点2");
	}
	else
	{
		menu.AddItem("add_point2", "添加坐标点2");
	}

	//所处坐标流程信息等
	menu.AddItem("show_position", "显示所处位置信息");

	menu.Display(client, MENU_TIME_FOREVER);
}

//菜单内容逻辑
int PointsMenuHandler(Menu menu, MenuAction action, int client, int param2)
{
	if (action == MenuAction_Select)
	{
		char sInfo[32];
		menu.GetItem(param2, sInfo, sizeof(sInfo));

		//处理穿墙
		if (StrEqual(sInfo, "noclip"))
		{
			MoveType movetype = GetEntityMoveType(client);
			if (movetype != MOVETYPE_NOCLIP)
			{
				SetEntityMoveType(client, MOVETYPE_NOCLIP);
				CPrintToChat(client, "{default}穿墙已{lightgreen}开启{default}.");
			}
			else
			{
				SetEntityMoveType(client, MOVETYPE_WALK);
				CPrintToChat(client, "{default}穿墙已{lightgreen}关闭{default}.");
			}
		}
		//坐标点
		else if (StrEqual(sInfo, "point1"))
		{
			TeleportEntity(client, g_fPoint1[client], NULL_VECTOR, NULL_VECTOR);
		}
		else if (StrEqual(sInfo, "delete_point1"))
		{
			Command_MarkPoint1(client, 0);
		}
		else if (StrEqual(sInfo, "point2"))
		{
			TeleportEntity(client, g_fPoint2[client], NULL_VECTOR, NULL_VECTOR);
		}
		else if (StrEqual(sInfo, "delete_point2"))
		{
			Command_MarkPoint2(client, 0);
		}
		else if (StrEqual(sInfo, "add_point1"))
		{
			Command_MarkPoint1(client, 0);
		}
		else if (StrEqual(sInfo, "add_point2"))
		{
			Command_MarkPoint2(client, 0);
		}
		//流程信息等
		else if (StrEqual(sInfo, "show_position"))
		{
			Command_ShowFlowPercentage(client, 0);
		}
		ShowPointsMenu(client);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	return 0;
}

//保存坐标
void SavePoints(int client)
{
	if (!g_bPluginEnabled)
	{
		return;
	}

	char sCookieValue[256];
	Format(sCookieValue, sizeof(sCookieValue), "%.2f,%.2f,%.2f|%.2f,%.2f,%.2f", 
		g_fPoint1[client][0], g_fPoint1[client][1], g_fPoint1[client][2],
		g_fPoint2[client][0], g_fPoint2[client][1], g_fPoint2[client][2]);

	SetClientCookie(client, g_hCookie, sCookieValue);
}

//坐标位置
void StringToVector(const char[] sString, float fVector[3])
{
	char sParts[3][16];
	ExplodeString(sString, ",", sParts, 3, 16);

	fVector[0] = StringToFloat(sParts[0]);
	fVector[1] = StringToFloat(sParts[1]);
	fVector[2] = StringToFloat(sParts[2]);
}

//以前是使用妹子模型来代替现在改成光柱了
void CreateWitchModel(int client, int point)
{
	if (point == 1)
	{
		//先取消可能存在的旧计时器
		if (g_hBeamTimer1[client] != null)
		{
			KillTimer(g_hBeamTimer1[client]);
			g_hBeamTimer1[client] = null;
		}
		
		//光柱创建
		CreateBeamEffect(client, 1);
		
		//1秒1循环的计时器
		g_hBeamTimer1[client] = CreateTimer(1.0, Timer_RefreshBeam1, GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		
		g_iWitchModel1[client] = 1; //标记为已设置点1
	}
	else if (point == 2)	//照搬点1
	{
		if (g_hBeamTimer2[client] != null)
		{
			KillTimer(g_hBeamTimer2[client]);
			g_hBeamTimer2[client] = null;
		}
		
		CreateBeamEffect(client, 2);
		
		g_hBeamTimer2[client] = CreateTimer(1.0, Timer_RefreshBeam2, GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
		
		g_iWitchModel2[client] = 1;
	}
}

// 创建光束效果
void CreateBeamEffect(int client, int point)
{
	float vPos[3];
	if (point == 1)
	{
		vPos = g_fPoint1[client];
	}
	else if (point == 2)
	{
		vPos = g_fPoint2[client];
	}

	//光柱直接一飞冲天就行
	float skyPos[3];
	skyPos = vPos;
	skyPos[2] += 1000.0;

	//环形底座稍微向上一些
	float ringPos[3];
	ringPos = vPos;
	ringPos[2] += 3.5;
	
	//颜色
	int colors[4];
	if (point == 1)
	{
		colors = {255, 0, 0, 186}; //红色,稍半透明
	}
	else if (point == 2)
	{
		colors = {0, 0, 255, 186}; //蓝色,稍半透明
	}

	/*
	//点对点光柱
	TE_SetupBeamPoints:
		const float[3] start
		Start position of the beam.

		const float[3] end
		End position of the beam.

		int ModelIndex
		Precached model index.

		int HaloIndex
		Precached model index.

		int StartFrame
		Initial frame to render.

		int FrameRate
		Beam frame rate.

		float Life
		Time duration of the beam.

		float Width
		Initial beam width.

		float EndWidth
		Final beam width.

		int FadeLength
		Beam fade time duration.

		float Amplitude
		Beam amplitude.

		const int[4] Color
		Color array (r, g, b, a).

		int Speed
		Speed of the beam.
	*/
	TE_SetupBeamPoints(vPos, skyPos, g_iBeamSprite, 0, 0, 0, 1.1, 1.2, 0.1, 1, 0.5, colors, 0);
	TE_SendToClient(client);
	
	/*
	//环形底座
	TE_SetupBeamRingPoint:
		const float[3] center
		Center position of the ring.

		float Start_Radius
		Initial ring radius.

		float End_Radius
		Final ring radius.

		int ModelIndex
		Precached model index.

		int HaloIndex
		Precached model index.

		int StartFrame
		Initial frame to render.

		int FrameRate
		Ring frame rate.

		float Life
		Time duration of the ring.

		float Width
		Beam width.

		float Amplitude
		Beam amplitude.

		const int[4] Color
		Color array (r, g, b, a).

		int Speed
		Speed of the beam.

		int Flags
		Beam flags.
	*/
	TE_SetupBeamRingPoint(ringPos, 0.0, 25.0, g_iBeamSprite, 0, 0, 0, 1.1, 0.2, 0.1, colors, 5, 0);
	TE_SendToClient(client);
}

//点1光柱计时器循环
Action Timer_RefreshBeam1(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	
	if (IsAlivePlayer(client) && g_bPoint1Set[client])
	{
		CreateBeamEffect(client, 1);
		return Plugin_Continue;
	}
	
	//否则如果玩家不在线或标记已取消,停止计时器
	g_hBeamTimer1[client] = null;
	return Plugin_Stop;
}

//点2光柱计时器循环
Action Timer_RefreshBeam2(Handle timer, any userid)
{
	int client = GetClientOfUserId(userid);
	
	if (IsAlivePlayer(client) && g_bPoint2Set[client])
	{
		CreateBeamEffect(client, 2);
		return Plugin_Continue;
	}
	
	//否则如果玩家不在线或标记已取消,停止计时器
	g_hBeamTimer2[client] = null;
	return Plugin_Stop;
}

//移除模型,直接移除计时器即可
void RemoveWitchModel(int client, int point)
{
	if (point == 1)
	{
		if (g_hBeamTimer1[client] != null)
		{
			KillTimer(g_hBeamTimer1[client]);
			g_hBeamTimer1[client] = null;
		}
		g_iWitchModel1[client] = -1;
	}
	else if (point == 2)
	{
		if (g_hBeamTimer2[client] != null)
		{
			KillTimer(g_hBeamTimer2[client]);
			g_hBeamTimer2[client] = null;
		}
		g_iWitchModel2[client] = -1;
	}
}

// 计算两点间的距离
float CalculateDistance(float point1[3], float point2[3])
{
	float dx = point1[0] - point2[0];
	float dy = point1[1] - point2[1];
	float dz = point1[2] - point2[2];
	return SquareRoot(dx * dx + dy * dy + dz * dz); //勾股定理是好东西
}

// 特感创建事件
public void OnEntityCreated(int entity, const char[] classname)
{
	if (!g_bPluginEnabled)
	{
		return;
	}

	if (StrEqual(classname, "smoker") || StrEqual(classname, "hunter") || StrEqual(classname, "boomer") || StrEqual(classname, "spitter") || StrEqual(classname, "jockey") || StrEqual(classname, "charger") || StrEqual(classname, "tank") || StrEqual(classname, "tank_rock") || StrEqual(classname, "witch"))
	{
		if (g_bPluginDmg)
		{
			SDKHook(entity, SDKHook_OnTakeDamage, OnTakeDamage_SI);
		}
		
		if (g_bPluginSIHighLight)
		{
			SetEntProp(entity, Prop_Send, "m_nGlowRange", 9999);
			SetEntProp(entity, Prop_Send, "m_iGlowType", 3);
			SetEntProp(entity, Prop_Send, "m_glowColorOverride", 0xFFC0CB);
		}
	}
}

//显示和计算攻击的伤害值
Action OnTakeDamage_SI(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if (!g_bPluginDmg || !g_bPluginEnabled)
	{
		return Plugin_Continue;
	}

	if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker))
	{
		// 实时显示每一枪/每一颗弹丸的伤害
		CPrintToChat(attacker, "{default}[!] {green}对目标造成 {lightgreen}%.2f点 {green}伤害.", damage);

		// 延迟显示 2.0 秒内的总伤害值
		if (g_bDamageActive[attacker])
		{
			// 如果攻击者已经在累积伤害，则将伤害值累加
			g_fDamageCache[attacker][victim] += damage;
			// 重置计时器
			KillTimer(g_hDamageTimer[attacker]);
			g_hDamageTimer[attacker] = CreateTimer(2.0, Timer_DisplayTotalDamage, attacker);
		}
		else
		{
			// 如果攻击者没有在累积伤害，则初始化伤害缓存并启动计时器
			for (int i = 1; i <= MaxClients; i++)
			{
				g_fDamageCache[attacker][i] = 0.0; // 清空缓存
			}
			g_fDamageCache[attacker][victim] = damage; // 记录当前伤害
			g_bDamageActive[attacker] = true; // 标记为正在累积伤害
			g_hDamageTimer[attacker] = CreateTimer(1.5, Timer_DisplayTotalDamage, attacker); // 启动计时器
		}
	}

	return Plugin_Continue;
}

//总伤计时回调
Action Timer_DisplayTotalDamage(Handle timer, any attacker)
{
	g_bDamageActive[attacker] = false; // 标记为不再累积伤害

	if (!IsClientInGame(attacker)) return Plugin_Stop; // 如果攻击者不在游戏中，停止计时器

	// 遍历所有玩家，显示总伤害值
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && g_fDamageCache[attacker][i] > 0.0)
		{
			// 显示总伤害值
			CPrintToChat(attacker, "{default}[总伤] {green}对目标造成的总伤害为: {lightgreen}%.2f点 {green}.", g_fDamageCache[attacker][i]);

			// 清空伤害缓存
			g_fDamageCache[attacker][i] = 0.0;
		}
	}

	return Plugin_Stop; // 停止计时器
}

// 特感生成菜单命令
Action Command_SpawnSI(int client, int args)
{
	if (!g_bPluginEnabled)
	{
		CPrintToChat(client, "{default}插件功能{green}已关闭{default}.");
		CPrintToChat(client, "{default}请使用 {green}!cvar bjkg 1 {default}打开插件开关.");
		return Plugin_Handled;
	}

	ShowSpawnSIMenu(client); // 显示特殊感染者生成菜单
	return Plugin_Handled;
}

// 显示特殊感染者生成菜单
void ShowSpawnSIMenu(int client)
{
	Menu menu = new Menu(SpawnSIMenuHandler);
	menu.SetTitle("功能菜单:");

	MoveType movetype = GetEntityMoveType(client);
	if (movetype != MOVETYPE_NOCLIP)
	{
		menu.AddItem("noclip", "开启穿墙");
	}
	else
	{
		menu.AddItem("noclip", "关闭穿墙");
	}

	//伤害显示开关
	char dmgDisplay[32];
	Format(dmgDisplay, sizeof(dmgDisplay), "伤害显示:%s", g_bPluginDmg ? "开启" : "关闭");
	menu.AddItem("dmg_toggle", dmgDisplay);

	//特感高亮开关
	char siHighlight[32];
	Format(siHighlight, sizeof(siHighlight), "特感高亮:%s", g_bPluginSIHighLight ? "开启" : "关闭");
	menu.AddItem("sihl_toggle", siHighlight);

	//重做冻结开关
	char freezeDisplay[32];
	ConVar freezeCvar = FindConVar("nb_blind");
	int freezeState = (freezeCvar != null) ? GetConVarInt(freezeCvar) : 0;
	Format(freezeDisplay, sizeof(freezeDisplay), "特感冻结:%s", freezeState == 0 ? "关闭" : "开启");
	menu.AddItem("freeze", freezeDisplay);

	menu.AddItem("smoker", "生成舌头");
	menu.AddItem("boomer", "生成胖子");
	menu.AddItem("hunter", "生成猎人");
	menu.AddItem("spitter", "生成口水");
	menu.AddItem("jockey", "生成猴子");
	menu.AddItem("charger", "生成牛牛");
	menu.AddItem("tank", "生成坦克");

	menu.Display(client, MENU_TIME_FOREVER);
}

//菜单功能回调处理
int SpawnSIMenuHandler(Menu menu, MenuAction action, int client, int param2)
{
	if (action == MenuAction_Select)
	{
		char sInfo[32];
		menu.GetItem(param2, sInfo, sizeof(sInfo));

		//处理穿墙
		if (StrEqual(sInfo, "noclip"))
		{
			MoveType movetype = GetEntityMoveType(client);
			if (movetype != MOVETYPE_NOCLIP)
			{
				SetEntityMoveType(client, MOVETYPE_NOCLIP);
				CPrintToChat(client, "{default}穿墙已{lightgreen}开启{default}.");
			}
			else
			{
				SetEntityMoveType(client, MOVETYPE_WALK);
				CPrintToChat(client, "{default}穿墙已{lightgreen}关闭{default}.");
			}

			ShowSpawnSIMenu(client);
			return 0;
		}

		//处理伤害显示开关回调
		if (StrEqual(sInfo, "dmg_toggle"))
		{
			// 切换伤害显示状态
			bool newState = !g_bPluginDmg;
			SetConVarBool(g_cvPluginDmg, newState);
			CPrintToChat(client, "{default}伤害显示已{lightgreen}%s{default}.", newState ? "开启" : "关闭");

			ShowSpawnSIMenu(client);
			return 0;
		}

		//处理特感高亮开关回调
		if (StrEqual(sInfo, "sihl_toggle"))
		{
			// 切换特感高亮状态
			bool newState = !g_bPluginSIHighLight;
			SetConVarBool(g_cvPluginSIHighLight, newState);
			CPrintToChat(client, "{default}特感高亮已{lightgreen}%s{default}.", newState ? "开启" : "关闭");

			ShowSpawnSIMenu(client);
			return 0;
		}

		//不再用sm_cvar nb_blind来处理
		//换更好的
		if (StrEqual(sInfo, "freeze"))
		{
			// 获取当前的冻结状态
			ConVar freezeCvar = FindConVar("nb_blind");
			if (freezeCvar != null)
			{
				int currentState = GetConVarInt(freezeCvar);
				if (currentState == 0)
				{
					SetConVarInt(freezeCvar, 1);
					CPrintToChat(client, "{default}特感冻结已{lightgreen}开启{default}.");
				}
				else
				{
					SetConVarInt(freezeCvar, 0);
					CPrintToChat(client, "{default}特感冻结已{lightgreen}关闭{default}.");
				}
			}

			ShowSpawnSIMenu(client);
			return 0;
		}

		// 获取玩家准心位置
		float vPos[3];
		GetClientEyePosition(client, vPos);
		float vAng[3];
		GetClientEyeAngles(client, vAng);
		TR_TraceRayFilter(vPos, vAng, MASK_SOLID, RayType_Infinite, TraceRayDontHitSelf, client);
		TR_GetEndPosition(vPos);

		// 生成特殊感染者
		char siType[32];
		if (StrEqual(sInfo, "smoker"))
		{
			siType = "smoker";
		}
		else if (StrEqual(sInfo, "boomer"))
		{
			siType = "boomer";
		}
		else if (StrEqual(sInfo, "hunter"))
		{
			siType = "hunter";
		}
		else if (StrEqual(sInfo, "spitter"))
		{
			siType = "spitter";
		}
		else if (StrEqual(sInfo, "jockey"))
		{
			siType = "jockey";
		}
		else if (StrEqual(sInfo, "charger"))
		{
			siType = "charger";
		}
		else if (StrEqual(sInfo, "tank"))
		{
			siType = "tank";
		}

		// 模仿的all4dead2.sp, 直接抄来使用StripAndExecuteClientCommand执行z_spawn命令
		StripAndExecuteClientCommand(client, "z_spawn", siType);

		// 重新显示菜单
		ShowSpawnSIMenu(client);
	}
	else if (action == MenuAction_End)
	{
		delete menu; // 删除菜单
	}
	return 0;
}

//显示流程百分比
Action Command_ShowFlowPercentage(int client, int args)
{
	if (!g_bPluginEnabled)
	{
		CPrintToChat(client, "{default}插件功能{lightgreen}已关闭{default}.");
		CPrintToChat(client, "{default}请使用 {green}!cvar bjkg 1 {default}打开插件开关.");
		return Plugin_Handled;
	}

	float currentPos[3];
	GetClientAbsOrigin(client, currentPos);

	float maxFlow = GetMapMaxFlowDistance();
	float currentFlowA = GetFlowFromPlayerPoint(client);

	if (currentFlowA != -9999.0)
	{
		float skyPosB[3];
		skyPosB = currentPos;
		skyPosB[2] += 50.0;	 //不需要很高

		int colors[4];
		colors = {221, 160, 221, 128};  //浅紫色,半透明

		TE_SetupBeamPoints(currentPos, skyPosB, g_iBeamSprite, 0, 0, 0, 3.5, 1.0, 0.0, 1, 0.5, colors, 0);
		TE_SendToClient(client);

		CPrintToChat(client, " ");
		CPrintToChat(client, "{default}当前位置坐标: ({lightgreen}%.2f{default}, {lightgreen}%.2f{default}, {lightgreen}%.2f{default})", currentPos[0], currentPos[1], currentPos[2]);

		float percent1 = (currentFlowA / maxFlow) * 100.0;
		CPrintToChat(client, "{default}当前位置坐标所处流程: {lightgreen}%.2f {default}/ {lightgreen}%.2f {default}| {green}%.2f%%", currentFlowA, maxFlow, percent1);
	}
	else
	{
		float navPos[3];
		float currentFlowB = GetFlowFromLastPlayerArea2(client, navPos);

		if ((navPos[0] != -9999.0) && (navPos[1] != -9999.0) && (navPos[2] != -9999.0) && (currentFlowB != -9999.0))
		{
			float skyPosA[3];
			skyPosA = navPos;
			skyPosA[2] += 50.0;	 //不需要很高

			int colors[4];
			colors = {221, 160, 221, 128};  //浅紫色,半透明

			TE_SetupBeamPoints(navPos, skyPosA, g_iBeamSprite, 0, 0, 0, 3.5, 1.0, 0.0, 1, 0.5, colors, 0);
			TE_SendToClient(client);

			CPrintToChat(client, " ");
			CPrintToChat(client, "{default}[!] 当前坐标({lightgreen}%.2f{default}, {lightgreen}%.2f{default}, {lightgreen}%.2f{default})获取不到地图流程!", currentPos[0], currentPos[1], currentPos[2]);

			float percent2 = (currentFlowB / maxFlow) * 100.0;
			CPrintToChat(client, "{default}[!] 可能是因为地形问题导致坐标接触不到导航网格等原因导致.");
			CPrintToChat(client, "{default}[!] 将直接采用最后经过的有效位置坐标.");
			CPrintToChat(client, "{default}采用最后位置坐标: ({lightgreen}%.2f{default}, {lightgreen}%.2f{default}, {lightgreen}%.2f{default})", navPos[0], navPos[1], navPos[2]);
			CPrintToChat(client, "{default}最后位置坐标所处流程: {lightgreen}%.2f {default}/ {lightgreen}%.2f {default}| {green}%.2f%%", currentFlowB, maxFlow, percent2);
		}
		else
		{
			CPrintToChat(client, " ");
			CPrintToChat(client, "{default}当前位置坐标: ({lightgreen}%.2f{default}, {lightgreen}%.2f{default}, {lightgreen}%.2f{default})", currentPos[0], currentPos[1], currentPos[2]);
			CPrintToChat(client, "{default}[!] 此坐标{green}获取不到{default}相应的地图流程值!!");
		}
	}
	
	return Plugin_Handled;
}

// 射线过滤, 防止射线击中无关的实体
bool TraceRayDontHitSelf(int entity, int mask, any data)
{
	return entity != data;
}

// 抄all4dead2的, 主要是为了执行z_spawn命令
void StripAndExecuteClientCommand(int client, const char[] command, const char[] arguments)
{
	// 获取命令的标志
	int flags = GetCommandFlags(command);
	// 移除作弊保护标志
	SetCommandFlags(command, flags & ~FCVAR_CHEAT);
	// 执行命令
	FakeClientCommand(client, "%s %s", command, arguments);
	// 恢复命令的标志
	SetCommandFlags(command, flags);
}

//清理
void CleanUpSomething(int client)
{
	// 清除第一个点的标记和计时器
	if (g_bPoint1Set[client])
	{
		g_bPoint1Set[client] = false;
		if (g_hBeamTimer1[client] != null)
		{
			KillTimer(g_hBeamTimer1[client]);
			g_hBeamTimer1[client] = null;
		}
	}

	// 清除第二个点的标记和计时器
	if (g_bPoint2Set[client])
	{
		g_bPoint2Set[client] = false;
		if (g_hBeamTimer2[client] != null)
		{
			KillTimer(g_hBeamTimer2[client]);
			g_hBeamTimer2[client] = null;
		}
	}

	// 直接清除客户端cookie中的标记点数据 我直接留空应该没事
	SetClientCookie(client, g_hCookie, "");

	// 清除由该玩家生成的特殊感染者
	if (g_aSpawnedSI[client] != null)
	{
		for (int i = 0; i < g_aSpawnedSI[client].Length; i++)
		{
			int entity = EntRefToEntIndex(g_aSpawnedSI[client].Get(i));
			if (entity != -1 && IsValidEntity(entity))
			{
				AcceptEntityInput(entity, "Kill"); //直接移除
			}
		}

		// 清空数组
		g_aSpawnedSI[client].Clear();
	}
}

//断开连接清理
public void OnClientDisconnect(int client)
{
	CleanUpSomething(client);
}

//回合结束清理
public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	//确保不会重复执行,这种情况在对抗模式里可能出现
	if (g_bRoundEndExecuted)
	{
		return;
	}
	g_bRoundEndExecuted = true;

	for (int client = 1; client <= MaxClients; client++)
	{
		CleanUpSomething(client);
	}
}

//获取生还最后有效坐标的流程距离
float GetFlowFromLastPlayerArea1(int client)
{
	if (!IsAlivePlayer(client))
	{
		return -9999.0;
	}
	
	//直接获取玩家最后所在的导航区域即可
	Address pNavArea = L4D_GetLastKnownArea(client);
	if (pNavArea == Address_Null)
	{
		return -9999.0;
	}
	
	//获取该导航区域的流程值
	return L4D2Direct_GetTerrorNavAreaFlow(pNavArea);
}

//获取生还最后有效坐标的流程距离和坐标
float GetFlowFromLastPlayerArea2(int client, float navPos[3])
{
	if (!IsAlivePlayer(client))
	{
		navPos[0] = navPos[1] = navPos[2] = -9999.0;
		return -9999.0;
	}
	
	//直接获取玩家最后所在的导航区域
	Address pNavArea = L4D_GetLastKnownArea(client);
	if (pNavArea == Address_Null)
	{
		navPos[0] = navPos[1] = navPos[2] = -9999.0;
		return -9999.0;
	}
	
	//获取导航区域的中心坐标
	L4D_GetNavAreaCenter(pNavArea, navPos);

	//获取该导航区域的流程值
	return L4D2Direct_GetTerrorNavAreaFlow(pNavArea);
}

/*
//获取生还最后有效坐标的流程距离的百分比
float GetPlayerFlowPercentage(int client)
{
	if (!IsAlivePlayer(client))
	{
		return -9999.0;
	}
	
	float flow = GetFlowFromLastPlayerArea(client);
	float maxFlowDistance = L4D2Direct_GetMapMaxFlowDistance();
	
	// 转换为百分比：当前流程值 / 地图最大流程距离 * 100
	return (maxFlowDistance > 0.0) ? ((flow / maxFlowDistance) * 100.0) : 0.0;
}
*/

//获取生还所在坐标的流程距离
float GetFlowFromPlayerPoint(int client)
{
	if (IsAlivePlayer(client))
	{
		float PlayerPos[3];
		GetClientAbsOrigin(client, PlayerPos);
		return GetFlowFromPoint(PlayerPos);
	}
	return -9999.0;
}

//获取坐标点流程距离
//可能因地形凹凸不平而找不到坐标返回-9999.0
float GetFlowFromPoint(float Pos[3])
{
	Address terrorNavPointer = L4D2Direct_GetTerrorNavArea(Pos);	//根据坐标查找对应导航网格指针
	if (terrorNavPointer == Address_Null)
	{
		return -9999.0;
	}
	return L4D2Direct_GetTerrorNavAreaFlow(terrorNavPointer);	   //最终返回输出指向的流程值
}

//获取地图最大流程距离
float GetMapMaxFlowDistance()
{
	return L4D2Direct_GetMapMaxFlowDistance();
}

/*
//流程值是否有效
bool IsValidDistanceFlow(float flow)
{
	return (flow != -9999.0);
}
*/

/*
//获取最远生还所在流程距离（照搬current.sp的实现）
float GetFarthestSurvivorFlow()
{
	float flow = 0.0, tmp_flow = 0.0;
	Address pNavArea;
	
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsAlivePlayer(client))
		{
			//获取玩家所在的导航区域
			pNavArea = L4D_GetLastKnownArea(client);
			if (pNavArea != Address_Null)
			{
				//获取该导航区域的流程距离
				tmp_flow = L4D2Direct_GetTerrorNavAreaFlow(pNavArea);
				// 取所有存活幸存者中的最大值
				flow = (flow > tmp_flow) ? flow : tmp_flow;
			}
		}
	}
	return flow;
}

//获取最远幸存者的流程百分比（照搬current.sp的实现）
float GetMaxSurvivorCompletion()
{
	float flowB = GetFarthestSurvivorFlow();
	float maxFlowDistance = GetMapMaxFlowDistance();
	
	//转换百分比: (当前流程距离数值 / 地图最大流程距离数值) x 100%
	//确保了不会小于0
	return (maxFlowDistance > 0.0) ? ((flow / maxFlowDistance) * 100.0) : 0.0;
}
*/

//是否为活着的生还玩家、特感玩家
bool IsAlivePlayer(int client)
{
	return (IsValidClient(client) && (GetClientTeam(client) == 2 || GetClientTeam(client) == 3) && IsPlayerAlive(client) && !IsFakeClient(client));
}

//有效客户端
bool IsValidClient(int client)
{
	return (IsValidClientIndex(client) && IsClientInGame(client) && !IsClientSourceTV(client) && !IsClientReplay(client));
}
