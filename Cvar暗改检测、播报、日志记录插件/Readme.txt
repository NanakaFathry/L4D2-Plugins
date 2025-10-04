插件项目魔改自:
https://github.com/SirPlease/L4D2-Competitive-Rework
的部分插件.
我负责写了日志记录插件(Cvar_DPL.sp)以及魔改ClientSetting.sp插件.
使得Cvar_DPL插件能够正常运作.

因此,在加载Cvar_DPL插件前,
如果是zm药抗插件的,则重新编译上面的:confoglcompmod.smx并替换,
然后再加载Cvar_DPL.smx。

如果是战役、非zm药抗插件等，则编译并加载TrackClientCvar_ZM.smx,
然后再加载Cvar_DPL.smx。

如果您的插件没有区分先后加载顺序，则一并放入Plugins里加载应该也是没问题的。

cvar_tracking.cfg文件一般置于cfg文件夹内,
然后在合适的地方,如:server.cfg等当中写入:
exec cvar_tracking.cfg
