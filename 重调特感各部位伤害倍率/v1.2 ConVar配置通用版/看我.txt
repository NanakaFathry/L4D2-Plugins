Seiunsky_Inf_LAH_Dmg_Na.smx
编译于sm1.12-7210,
其他版本的sourcemod只要正常编译成功我想应该也能用.

游戏原版各部位伤害倍率是:
head-头部-4倍
chest-胸腔部位(仅smoker,hunter,boomer有)-1倍
body-身体(smoker,hunter,boomer则是胃部)-1.25倍
arm-手臂-1倍
leg0腿部-0.75倍

而此插件核心功能是重新赋值各倍率,比如说设置:
sm_inf_lah_dmg_smoker_head 4.25
即,重新设置smoker头部伤害倍率是4.25倍而非原版的4倍.
sm_inf_lah_dmg_wp则是用来指定能够生效的武器.

v1.2版本是直接将所有的:
sm_inf_lah_dmg_*_head
sm_inf_lah_dmg_*_chest  //(有些特感没有这个)
sm_inf_lah_dmg_*_body
sm_inf_lah_dmg_*_arm
sm_inf_lah_dmg_*_leg
数值应用在：
sm_inf_lah_dmg_wp
所配置的武器之上,
即一劳永逸重新设置相应针对于特感各部位的伤害倍率.

比如说设置:
sm_inf_lah_dmg_wp "weapon_sniper_scout,weapon_sniper_awp"
则表示鸟狙(weapon_sniper_scout),大狙(weapon_sniper_awp)这两把武器全部应用:
sm_inf_lah_dmg_*_head
sm_inf_lah_dmg_*_chest
sm_inf_lah_dmg_*_body
sm_inf_lah_dmg_*_arm
sm_inf_lah_dmg_*_leg
所设置的倍率.

如果要详细设置不同武器针对不同特感部位不同伤害倍率的,则使用v2.0重制版.
