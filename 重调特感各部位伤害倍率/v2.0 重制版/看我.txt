Seiunsky_Inf_LAH_Dmg.smx
编译于sm1.12-7210,
其他版本的sourcemod只要正常编译成功我想应该也能用.

游戏原版各部位伤害倍率是:
head-头部-4倍
chest-胸腔部位(仅smoker,hunter,boomer有)-1倍
body-身体(smoker,hunter,boomer则是胃部)-1.25倍
arm-手臂-1倍
leg0腿部-0.75倍

此v2.0重制版插件,其核心功能是能够更加详细地重新调整:
某武器 针对 某特感 的 某部位 的 伤害倍率.
相比v1.2版本,此版本配置比较繁琐一点,
但相反只有这样才能做到更详细地配置自己想要的内容.

插件加载后,在server.cfg或其他配置文件内设置诸如:
sm_skwp weapon_sniper_scout charger_head 5.00
即,重新设置鸟狙(weapon_sniper_scout)这把武器针对charger的头部(charger_head)的伤害倍率为5.00倍,而非原版的4倍.
对于没有设置到的部位/特感/武器,则还是基于原版游戏的判断.

而插件中的:
sm_*_hurt_x
则是设置此特感在控住生还时,
除了头部以外,其余部位所受到伤害的额外增益,
设置1.00则表示1倍,也意味着关闭此功能.

比如设置:
sm_hunter_hurt_x 1.45
则表示hunter控住生还时,除了头部外,其余部位受到伤害将:
基于原版/此插件调整后的伤害倍率 x 1.45倍.

其他功能:
sm_skwp_list : 列出全部配置.
sm_skwp_clear [武器] : 仅清除该武器的配置.
sm_skwp_clear all : 清除全部配置.
