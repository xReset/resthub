-- R3ST Hub / Anims v2026-09-01.11 (2026-09-01)
-- M7-derived local animation pack browser: 21 custom, 35 Roblox, 24 UGC.
-- Rung 3: writes stock Animate IDs and restarts its server-created Animator tracks.
-- Server sees: normal replicated character tracks; no remotes fired.
-- Proof: m7_analyzer v6 capture; MIC UP dump 2026-08-27T15-42-06Z:
-- ENFORCEMENT=0, REPORTING=0, CLIENT INSPECTION=0, LOG MONITORING=0.
-- Re-inject safe; K = restore originals + unload. RightShift = hide/show.
-- Changelog:
--   .11 split panel detach from controller disable. Hub route/module reloads
--      remove only the Anims panel; applied animations persist. A clear ON/OFF
--      control owns apply/restore, defaults OFF, and persists explicitly.
--   .10 frontend rebuilt on the hub's own tokens and mounted through
--      getgenv().__R3ST_HOST, so Anims is a tab inside hub.lua instead of a
--      second window. Two-column pack grid, per-tab counts, re-apply button.
--      Standalone inject still opens its own window. Backend untouched.
--   .9 R3ST Hub frontend; animation backend and lifecycle unchanged.
--   .8 UGC slots resolved from each Roblox bundle's own assets, not from click
--      timing: no cross-pack idle/swim bleed, and 5 unworn bundles recovered.
--   .7 RightShift hide/show works even when Roblox marks Shift processed.
--   .6 separate active Animate state from unload baseline; migrate prior builds.
--   .5 match M7 stock Core-priority playback; hard-destroy tracks during restart.
--   .4 preserve false Animate.Disabled baseline during synchronous restore.
--   .3 migrate v1's deferred teardown state before taking controller ownership.
--   .2 exclusive track controller; hard stop/destroy on switch and unload.
--   .1 captured catalog, custom/Roblox/UGC tabs, per-slot sources, persistence.

local BUILD_VERSION = "anims-2026-09-01.11"
local GKEY = "__ANIMS_GUI"
local CONFIG_FILE = "anims_config.json"
local LOG_FILE = "logs/anims.log"

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local localPlayer = Players.LocalPlayer
local G = getgenv()

local previousBuild = G[GKEY] and G[GKEY].build
if G[GKEY] and type(G[GKEY].destroy) == "function" then
	pcall(G[GKEY].destroy)
end
if previousBuild then
	local previousAnimate = localPlayer.Character and localPlayer.Character:FindFirstChild("Animate")
	if previousAnimate and previousAnimate:IsA("LocalScript") then previousAnimate.Disabled = false end
end

local CATALOG_JSON = [====[{"sourceBuild":"m7-analyzer-2026-08-27.6","eventCount":12057,"ugcSource":"roblox bundle assets","packs":[{"name":"Vogue","category":"Custom","bundleId":null,"slots":{"swim":"135912650342079","idle1":"116765159485288","idle2":"116765159485288","swimidle":"135912650342079","run":"86271392429456","fall":"105583797703463","walk":"86271392429456","climb":"86885530543449","jump":"77167361159844"}},{"name":"Catwalk","category":"Custom","bundleId":null,"slots":{"swim":"135912650342079","idle1":"98739374128375","idle2":"75810364031837","swimidle":"135912650342079","run":"97847888500780","fall":"105583797703463","walk":"97847888500780","climb":"86885530543449","jump":"77167361159844"}},{"name":"Possessed","category":"Custom","bundleId":null,"slots":{"swim":"135912650342079","idle1":"80103653497738","idle2":"75794256017298","swimidle":"135912650342079","run":"88508412373927","fall":"105583797703463","walk":"88508412373927","climb":"86885530543449","jump":"77167361159844"}},{"name":"Walking Dead","category":"Custom","bundleId":null,"slots":{"swim":"135912650342079","idle1":"126838128163810","idle2":"115485274167727","swimidle":"135912650342079","run":"96819546392344","fall":"105583797703463","walk":"96819546392344","climb":"86885530543449","jump":"77167361159844"}},{"name":"Scared","category":"Custom","bundleId":null,"slots":{"swim":"135912650342079","idle1":"131382303107033","idle2":"131382303107033","swimidle":"135912650342079","run":"128578785610052","fall":"105583797703463","walk":"128578785610052","climb":"86885530543449","jump":"77167361159844"}},{"name":"Flip Vogue","category":"Custom","bundleId":null,"slots":{"swim":"135912650342079","idle1":"128436335892775","idle2":"128436335892775","swimidle":"135912650342079","run":"110033677841515","fall":"105583797703463","walk":"110033677841515","climb":"86885530543449","jump":"77167361159844"}},{"name":"Tough Catwalk","category":"Custom","bundleId":null,"slots":{"swim":"135912650342079","idle1":"71307846281220","idle2":"75810364031837","swimidle":"135912650342079","run":"97847888500780","fall":"105583797703463","walk":"97847888500780","climb":"86885530543449","jump":"77167361159844"}},{"name":"Maria","category":"Custom","bundleId":null,"slots":{"swim":"135912650342079","idle1":"102439655497210","idle2":"131382303107033","swimidle":"135912650342079","run":"128578785610052","fall":"105583797703463","walk":"128578785610052","climb":"86885530543449","jump":"77167361159844"}},{"name":"Yagani","category":"Custom","bundleId":null,"slots":{"swim":"135912650342079","idle1":"120525965549187","idle2":"120525965549187","swimidle":"135912650342079","run":"81088957780074","fall":"105583797703463","walk":"81088957780074","climb":"86885530543449","jump":"77167361159844"}},{"name":"Stage Walk","category":"Custom","bundleId":null,"slots":{"swim":"135912650342079","idle1":"111408250277560","idle2":"111408250277560","swimidle":"135912650342079","run":"71714422728827","fall":"105583797703463","walk":"71714422728827","climb":"86885530543449","jump":"77167361159844"}},{"name":"Nicki Minaj","category":"Custom","bundleId":null,"slots":{"swim":"135912650342079","idle1":"124843880707004","idle2":"124843880707004","swimidle":"135912650342079","run":"103145593690285","fall":"105583797703463","walk":"103145593690285","climb":"86885530543449","jump":"77167361159844"}},{"name":"Fn Catwalk","category":"Custom","bundleId":null,"slots":{"swim":"135912650342079","idle1":"101395235813499","idle2":"101395235813499","swimidle":"135912650342079","run":"79786759005429","fall":"105583797703463","walk":"79786759005429","climb":"86885530543449","jump":"77167361159844"}},{"name":"Dead Crawl","category":"Custom","bundleId":null,"slots":{"swim":"135912650342079","idle1":"107999093858726","idle2":"106320514159313","swimidle":"135912650342079","run":"109318260839099","fall":"105583797703463","walk":"109318260839099","climb":"86885530543449","jump":"77167361159844"}},{"name":"Witch","category":"Custom","bundleId":null,"slots":{"swim":"135912650342079","idle1":"118244282258569","idle2":"131414686544529","swimidle":"135912650342079","run":"88090745346562","fall":"105583797703463","walk":"88090745346562","climb":"86885530543449","jump":"77167361159844"}},{"name":"Gmod","category":"Custom","bundleId":null,"slots":{"swim":"135912650342079","idle1":"116728112189619","idle2":"101197238583271","swimidle":"135912650342079","run":"113718116290824","fall":"111081589891568","walk":"93080497127998","climb":"116184760543682","jump":"131814798893284"}},{"name":"Minify","category":"Custom","bundleId":null,"slots":{"swim":"135912650342079","idle1":"125884328313129","idle2":"111913275466363","swimidle":"135912650342079","run":"85887415033585","fall":"85887415033585","walk":"85887415033585","climb":"117434745972345","jump":"85887415033585"}},{"name":"Forsaken","category":"Custom","bundleId":null,"slots":{"swim":"135912650342079","idle1":"98946450554814","idle2":"98946450554814","swimidle":"135912650342079","run":"108891884872744","fall":"108891884872744","walk":"119545916455209","climb":"119545916455209","jump":"108891884872744"}},{"name":"Slender Man","category":"Custom","bundleId":null,"slots":{"swim":"135912650342079","idle1":"115268975352566","idle2":"91916385599385","swimidle":"135912650342079","run":"134411626334329","fall":"128642113698397","walk":"134010853417610","climb":"128642113698397","jump":"111946345092187"}},{"name":"Sassy","category":"Custom","bundleId":null,"slots":{"swim":"135912650342079","idle1":"91469902979273","idle2":"127234839786939","swimidle":"135912650342079","run":"85475131476587","fall":"123691927890594","walk":"81902773529444","climb":"129301741044313","jump":"115952229051580"}},{"name":"Retro","category":"Custom","bundleId":null,"slots":{"swim":"135912650342079","idle1":"118461919095618","idle2":"100320071206202","swimidle":"135912650342079","run":"107806791584829","fall":"105583797703463","walk":"107806791584829","climb":"121075390792786","jump":"83257714233706"}},{"name":"E-Girl","category":"Custom","bundleId":null,"slots":{"swim":"135912650342079","idle1":"132984592941585","idle2":"124200992648318","swimidle":"135912650342079","run":"90449724957683","fall":"110319921537712","walk":"106767496454996","climb":"82587632175618","jump":"83380602503991"}},{"name":"Cartoony","category":"Roblox","bundleId":null,"slots":{"swim":"10921138209","idle1":"10921132962","idle2":"10921133721","swimidle":"10921139478","run":"10921135644","fall":"10921136539","walk":"10921140719","climb":"10921132092","jump":"10921137402"}},{"name":"Levitation","category":"Roblox","bundleId":null,"slots":{"swim":"10921253142","idle1":"10921248039","idle2":"10921248831","swimidle":"10921253767","run":"10921250460","fall":"10921251156","walk":"10921255446","climb":"10921247141","jump":"10921252123"}},{"name":"Robot","category":"Roblox","bundleId":null,"slots":{"swim":"10921281000","idle1":"10921272275","idle2":"10921273958","swimidle":"10921281964","run":"10921276116","fall":"10921278648","walk":"10921283326","climb":"10921271391","jump":"10921279832"}},{"name":"Stylish","category":"Roblox","bundleId":null,"slots":{"swim":"10921295495","idle1":"10921288909","idle2":"10921290167","swimidle":"10921297391","run":"10921291831","fall":"10921293373","walk":"10921298616","climb":"10921286911","jump":"10921294559"}},{"name":"Superhero","category":"Roblox","bundleId":null,"slots":{"swim":"10921352344","idle1":"10921344533","idle2":"10921345304","swimidle":"10921353442","run":"616163682","fall":"10921350320","walk":"10921355261","climb":"10921343576","jump":"10921351278"}},{"name":"Zombie","category":"Roblox","bundleId":null,"slots":{"swim":"10921161002","idle1":"10921155160","idle2":"10921155867","swimidle":"10922757002","run":"10921157929","fall":"10921159222","walk":"10921162768","climb":"10921154678","jump":"10921160088"}},{"name":"Ninja","category":"Roblox","bundleId":null,"slots":{"swim":"10921150788","idle1":"10921144709","idle2":"10921145797","swimidle":"10921151661","run":"10921148209","fall":"10921148939","walk":"10921152678","climb":"10921143404","jump":"10921149743"}},{"name":"Mage","category":"Roblox","bundleId":null,"slots":{"swim":"10921309319","idle1":"10921301576","idle2":"10921302207","swimidle":"10921310341","run":"10921306285","fall":"10921307241","walk":"10921312010","climb":"10921300839","jump":"10921308158"}},{"name":"Toy","category":"Roblox","bundleId":null,"slots":{"swim":"10921108971","idle1":"10921101664","idle2":"10921102574","swimidle":"10921110146","run":"10921104374","fall":"10921105765","walk":"10921111375","climb":"10921100400","jump":"10921107367"}},{"name":"Elder","category":"Roblox","bundleId":null,"slots":{"swim":"10921324408","idle1":"10921315373","idle2":"10921316709","swimidle":"10921325443","run":"10921320299","fall":"10921321317","walk":"10921326949","climb":"10921314188","jump":"10921322186"}},{"name":"Vampire","category":"Roblox","bundleId":null,"slots":{"swim":"10921340419","idle1":"10921330408","idle2":"10921333667","swimidle":"10921341319","run":"10921336997","fall":"10921337907","walk":"10921342074","climb":"10921329322","jump":"1083218792"}},{"name":"Werewolf","category":"Roblox","bundleId":null,"slots":{"swim":"10921243048","idle1":"10921230744","idle2":"10921232093","swimidle":"10921244018","run":"10921240218","fall":"10921241244","walk":"10921244891","climb":"10921229866","jump":"10921242013"}},{"name":"Oldschool","category":"Roblox","bundleId":null,"slots":{"swim":"10921044000","idle1":"10921034824","idle2":"10921036806","swimidle":"10921045006","run":"10921039308","fall":"10921040576","walk":"10921046031","climb":"10921032124","jump":"10921042494"}},{"name":"Astronaut","category":"Roblox","bundleId":null,"slots":{"swim":"10921063569","idle1":"10921054344","idle2":"10921055107","swimidle":"10922582160","run":"10921057244","fall":"10921061530","walk":"10980888364","climb":"10921053544","jump":"10921062673"}},{"name":"Bubbly","category":"Roblox","bundleId":null,"slots":{"swim":"10921125160","idle1":"10921117521","idle2":"10921118894","swimidle":"10921125935","run":"10921121197","fall":"10921122579","walk":"10921127095","climb":"10921116196","jump":"10921123517"}},{"name":"Knight","category":"Roblox","bundleId":null,"slots":{"swim":"750784579","idle1":"750781874","idle2":"750782770","swimidle":"750785176","run":"750783738","fall":"750780242","walk":"750785693","climb":"750779899","jump":"750782230"}},{"name":"Pirate","category":"Roblox","bundleId":null,"slots":{"swim":"134591743181628","idle1":"133806214992291","idle2":"94970088341563","swimidle":"98854111361360","run":"81024476153754","fall":"92294537340807","walk":"109168724482748","climb":"119377220967554","jump":"116936326516985"}},{"name":"Catwalk Glam","category":"Roblox","bundleId":null,"slots":{"swim":"4708189360","idle1":"4708191566","idle2":"4708192150","swimidle":"4708190607","run":"4708192705","fall":"4708186162","walk":"4708193840","climb":"4708184253","jump":"4708188025"}},{"name":"Stylized Female","category":"Roblox","bundleId":null,"slots":{"swim":"1014406523","idle1":"1014390418","idle2":"1014398616","swimidle":"1014411816","run":"1014401683","fall":"1014384571","walk":"1014401683","climb":"1014380606","jump":"1014394726"}},{"name":"Cowboy","category":"Roblox","bundleId":null,"slots":{"swim":"941018893","idle1":"941003647","idle2":"941013098","swimidle":"941025398","run":"941015281","fall":"941000007","walk":"941015281","climb":"940996062","jump":"941008832"}},{"name":"Princess","category":"Roblox","bundleId":null,"slots":{"swim":"1132500520","idle1":"1132473842","idle2":"1132477671","swimidle":"1132506407","run":"1132494274","fall":"1132469004","walk":"1132494274","climb":"1132461372","jump":"1132489853"}},{"name":"Sneaky","category":"Roblox","bundleId":null,"slots":{"swim":"1151204998","idle1":"1149612882","idle2":"1150842221","swimidle":"1151221899","run":"1150967949","fall":"1148863382","walk":"1150967949","climb":"1148811837","jump":"1150944216"}},{"name":"Patrol","category":"Roblox","bundleId":null,"slots":{"swim":"1212852603","idle1":"1212900985","idle2":"1212954651","swimidle":"1151221899","run":"1212980348","fall":"1212900995","walk":"1212980348","climb":"1148811837","jump":"1212954642"}},{"name":"Popstar","category":"Roblox","bundleId":null,"slots":{"swim":"1070009914","idle1":"1069977950","idle2":"1069987858","swimidle":"1070012133","run":"1070001516","fall":"1069973677","walk":"1070001516","climb":"1069946257","jump":"1069984524"}},{"name":"Confident","category":"Roblox","bundleId":null,"slots":{"swim":"11600212676","idle1":"17172918855","idle2":"17173014241","swimidle":"11600213505","run":"11600211410","fall":"11600206437","walk":"11600249883","climb":"11600205519","jump":"11600210487"}},{"name":"Realistic","category":"Roblox","bundleId":null,"slots":{"swim":"10921264784","idle1":"4417977954","idle2":"4417978624","swimidle":"10921265698","run":"4417979645","fall":"10921262864","walk":"10921269718","climb":"10921257536","jump":"10921263860"}},{"name":"Mr Toilet","category":"Roblox","bundleId":null,"slots":{"swim":"10921264784","idle1":"3303162274","idle2":"3303162549","swimidle":"10921265698","run":"3236836670","fall":"10921262864","walk":"3303162967","climb":"10921257536","jump":"10921263860"}},{"name":"Ud'zal","category":"Roblox","bundleId":null,"slots":{"swim":"132697394189921","idle1":"92080889861410","idle2":"74451233229259","swimidle":"79090109939093","run":"117333533048078","fall":"129773241321032","walk":"110358958299415","climb":"134630013742019","jump":"119846112151352"}},{"name":"NFL","category":"Roblox","bundleId":null,"slots":{"swim":"18537389531","idle1":"18537376492","idle2":"18537371272","swimidle":"18537387180","run":"18537384940","fall":"18537367238","walk":"18537392113","climb":"18537363391","jump":"18537380791"}},{"name":"adidas Sports","category":"Roblox","bundleId":null,"slots":{"swim":"99384245425157","idle1":"118832222982049","idle2":"76049494037641","swimidle":"113199415118199","run":"72301599441680","fall":"121152442762481","walk":"92072849924640","climb":"131326830509784","jump":"104325245285198"}},{"name":"Wicked Popular","category":"Roblox","bundleId":null,"slots":{"swim":"18747073181","idle1":"18747067405","idle2":"18747063918","swimidle":"18747071682","run":"18747070484","fall":"18747062535","walk":"18747074203","climb":"18747060903","jump":"18747069148"}},{"name":"No-Boundaries","category":"Roblox","bundleId":null,"slots":{"swim":"16738339158","idle1":"16738333868","idle2":"16738334710","swimidle":"16738339817","run":"16738337225","fall":"16738333171","walk":"16738340646","climb":"16738332169","jump":"16738336650"}},{"name":"Bold","category":"Roblox","bundleId":null,"slots":{"swim":"10921264784","idle1":"10921259953","idle2":"10921258489","swimidle":"10921265698","run":"10921261968","fall":"10921262864","walk":"10921269718","climb":"10921257536","jump":"10921263860"}},{"name":"Rthro","category":"Roblox","bundleId":null,"slots":{"swim":"913384386","idle1":"507766388","idle2":"507766666","swimidle":"913389285","run":"913376220","fall":"507767968","walk":"913402848","climb":"507765644","jump":"507765000"}},{"name":"Default","category":"Roblox","bundleId":null,"slots":{"swim":"10921324408","idle1":"10921315373","idle2":"10921316709","swimidle":"10921325443","run":"10921320299","fall":"10921321317","walk":"10921326949","climb":"10921314188","jump":"10921322186"}},{"name":"Body Builder","category":"UGC","bundleId":"94555714074535","slots":{"walk":"128946173910218","run":"93073957539704","jump":"90906915247882","fall":"135191104747316","climb":"71219419891675","idle1":"95545698545591","idle2":"95537840710100","swim":"71041658209093","swimidle":"106871097390426"}},{"name":"Ninja Animation V1","category":"UGC","bundleId":"80006416826964","slots":{"walk":"112995814702011","run":"92393061064066","jump":"137095845923683","fall":"108903178590227","climb":"116969260695858","idle1":"100586619705973","idle2":"80917490567255","swim":"80029624718031","swimidle":"140040548086906"}},{"name":"Nonchalant Casual School Boy","category":"UGC","bundleId":"132394592647887","slots":{"walk":"126045125708041","run":"121819291063555","jump":"77167361159844","fall":"105583797703463","climb":"86885530543449","idle1":"104866296805499","idle2":"96545363481011","swim":"135912650342079","swimidle":"128559436278221"}},{"name":"FNAF Nightmare Foxy Pack","category":"UGC","bundleId":"265704867658210","slots":{"walk":"70920775888897","run":"88229668693997","jump":"130366495998037","fall":"122143026433332","climb":"71981380239964","idle1":"117707827528185","idle2":"117707827528185","swim":"137145838591965","swimidle":"125792962376666"}},{"name":"Hakari Jujutsu Kaisen Pack","category":"UGC","bundleId":"77390856608677","slots":{"walk":"117575926245382","run":"105145348112173","jump":"137134050102669","fall":"96885544620726","climb":"109444449029609","idle1":"119857481234866","idle2":"119857481234866","swim":"83941858525796","swimidle":"71065315520097"}},{"name":"Miles Morales SpiderMan Pack","category":"UGC","bundleId":"74003310381425","slots":{"walk":"96297006104199","run":"82692124798690","jump":"95290746827335","fall":"80147555973971","climb":"97632113550265","idle1":"72205828872410","idle2":"72205828872410","swim":"79474619658975","swimidle":"130699605984679"}},{"name":"R6 Animatronic Animation Pack","category":"UGC","bundleId":"139749827756407","slots":{"walk":"87720446630981","run":"89847356249127","jump":"76885599016656","fall":"92670347149679","climb":"121214744586543","idle1":"78749712160478","idle2":"78749712160478","swim":"87503260841474","swimidle":"79148694033123"}},{"name":"R6 Floating","category":"UGC","bundleId":"269271274753937","slots":{"walk":"104114015677596","run":"127586457394376","jump":"75656028149361","fall":"96313335726495","climb":"72767050718397","idle1":"108466298474104","idle2":"108466298474104","swim":"97163747765223","swimidle":"79497850973351"}},{"name":"crazy animation pack","category":"UGC","bundleId":"268645960939990","slots":{"walk":"78148745848713","run":"86677015433490","jump":"95580004936450","fall":"94583039719377","climb":"73891864077432","idle1":"112642858941703","idle2":"83132839243166","swim":"135107551239282","swimidle":"95776145135017"}},{"name":"Cool Stealthy Ninja","category":"UGC","bundleId":"54197748716396","slots":{"walk":"107600770643368","run":"95799909787600","jump":"72907104884810","fall":"96698919949815","climb":"87644801048811","idle1":"113365131037852","idle2":"113365131037852","swim":"114157449101009","swimidle":"72689493009208"}},{"name":"HUG Animation Pack","category":"UGC","bundleId":"103192406771829","slots":{"walk":"113000062129384","run":"89915073489447","jump":"108199224742046","fall":"120542432911868","climb":"120220198169944","idle1":"94079287414092","idle2":"94079287414092","swim":"91066223167090","swimidle":"121774220343784"}},{"name":"Gothic Doll","category":"UGC","bundleId":"33371475635713","slots":{"walk":"85880632888189","run":"78142288580771","jump":"118989321850886","fall":"102278745185462","climb":"125404548923152","idle1":"82871082206432","idle2":"82871082206432","swim":"107925722334092","swimidle":"130124590538326"}},{"name":"Cute Iconic Kawaii Diva Model","category":"UGC","bundleId":"266767083985551","slots":{"walk":"129037194783554","run":"116843185594138","jump":"72321726457810","fall":"103832771350187","climb":"72597712622183","idle1":"72649463587201","idle2":"76286445384987","swim":"109835552551212","swimidle":"77733194587960"}},{"name":"Man Anime Chad Aura","category":"UGC","bundleId":"272613581387299","slots":{"walk":"80060692321926","run":"129395769202970","jump":"88291985693006","fall":"125181922461229","climb":"103805554248226","idle1":"91785514757752","idle2":"92643582088399","swim":"113023394699888","swimidle":"90195079668205"}},{"name":"Zombie Animation Pack","category":"UGC","bundleId":"261977891265696","slots":{"walk":"105336965582168","run":"74087833185591","jump":"84800470186682","fall":"131246475419384","climb":"77310374305262","idle1":"84264397793956","idle2":"134315031447583","swim":"132152041104351","swimidle":"132528549088833"}},{"name":"Loopy","category":"UGC","bundleId":"8708677391544","slots":{"walk":"81880815952006","run":"131975318740744","jump":"87963591628143","fall":"93603248848487","climb":"123542371248024","idle1":"129380837648712","idle2":"79199053338041","swim":"113156417218564","swimidle":"83967060403191"}},{"name":"Handstand","category":"UGC","bundleId":"146941576284599","slots":{"walk":"111637096013136","run":"102164776538515","jump":"93344140592278","fall":"121327103236642","climb":"97665267797097","idle1":"93924053429572","idle2":"117779568318230","swim":"113286816721050","swimidle":"110856471158101"}},{"name":"Xannedo's Vampire Flying Levitation Pack","category":"UGC","bundleId":"253024838694544","slots":{"walk":"139254664631008","run":"100647784997527","jump":"95064213072146","fall":"132405136851846","climb":"99320273662560","idle1":"118777067306042","idle2":"75122775273502","swim":"98319787273940","swimidle":"100023464250195"}},{"name":"Crew Plug Animation Pack","category":"UGC","bundleId":"278421327540123","slots":{"walk":"135166379634587","run":"120931752122340","jump":"118922585222897","fall":"73597153995912","climb":"122621387779366","idle1":"98484876377375","idle2":"82483118996338","swim":"91350045927114","swimidle":"137981065723249"}},{"name":"\ud83d\udc7c Angelic","category":"UGC","bundleId":"3010761716106","slots":{"walk":"136289728065245","run":"71819534610952","jump":"121912976998432","fall":"130358971169296","climb":"136679989223658","idle1":"136073315541495","idle2":"80617266157747","swim":"106842072364192","swimidle":"92765250944908"}},{"name":"Sans Animation Pack","category":"UGC","bundleId":"280320546845566","slots":{"walk":"106932383325706","run":"135169158481655","jump":"81687708257710","fall":"110951440254500","climb":"78209645550238","idle1":"100882509347535","idle2":"91775014506081","swim":"85898217404527","swimidle":"140389148673061"}},{"name":"R6 Floating Aura Jet Booster","category":"UGC","bundleId":"199574350545528","slots":{"walk":"109261813936812","run":"133497153421891","jump":"123600716433859","fall":"81205807325400","climb":"133092510272282","idle1":"83865643408220","idle2":"83865643408220","swim":"140151564591887","swimidle":"90446289864260"}},{"name":"Scaredy Cat Pack","category":"UGC","bundleId":"188538622570221","slots":{"walk":"100872837030277","run":"85087687174988","jump":"125966094036473","fall":"99787107516401","climb":"121175403458070","idle1":"130322395100479","idle2":"130322395100479","swim":"139035197932207","swimidle":"73140564194397"}},{"name":"Sleepy Guy Pack","category":"UGC","bundleId":"214510916015602","slots":{"walk":"86756305449480","run":"101419004957653","jump":"75261854055422","fall":"88967088093064","climb":"140629373836065","idle1":"133998508183967","idle2":"133998508183967","swim":"132836213181804","swimidle":"113198788440697"}}]}]====]
local decoded = HttpService:JSONDecode(CATALOG_JSON)
local PACKS = decoded.packs
local PACK_BY_NAME = {}
for _, pack in ipairs(PACKS) do PACK_BY_NAME[pack.name] = pack end

local SLOT_ORDER = { "idle1", "idle2", "walk", "run", "jump", "fall", "climb", "swim", "swimidle" }
local SLOT_LABEL = {
	idle1 = "Idle 1", idle2 = "Idle 2", walk = "Walk", run = "Run",
	jump = "Jump", fall = "Fall", climb = "Climb", swim = "Swim", swimidle = "Swim Idle",
}
local Config = {
	enabled = false,
	selectedPack = "Vogue",
	activeTab = "Custom",
	windowX = 0.5,
	windowY = 0.5,
	hidden = false,
	slotSources = {},
}

local function loadConfig()
	local ok, raw = pcall(readfile, CONFIG_FILE)
	if not ok or type(raw) ~= "string" then return end
	local decodedOk, saved = pcall(HttpService.JSONDecode, HttpService, raw)
	if not decodedOk or type(saved) ~= "table" then return end
	if type(saved.enabled) == "boolean" then Config.enabled = saved.enabled end
	if type(saved.selectedPack) == "string" and PACK_BY_NAME[saved.selectedPack] then Config.selectedPack = saved.selectedPack end
	if saved.activeTab == "Custom" or saved.activeTab == "Roblox" or saved.activeTab == "UGC" or saved.activeTab == "Slots" then Config.activeTab = saved.activeTab end
	if type(saved.windowX) == "number" then Config.windowX = math.clamp(saved.windowX, 0, 1) end
	if type(saved.windowY) == "number" then Config.windowY = math.clamp(saved.windowY, 0, 1) end
	if type(saved.hidden) == "boolean" then Config.hidden = saved.hidden end
	if type(saved.slotSources) == "table" then
		for _, slot in ipairs(SLOT_ORDER) do
			local source = saved.slotSources[slot]
			if type(source) == "string" and PACK_BY_NAME[source] then Config.slotSources[slot] = source end
		end
	end
end

local saveToken = 0
local function saveConfig()
	saveToken += 1
	local token = saveToken
	task.delay(0.4, function()
		if token ~= saveToken then return end
		local ok, raw = pcall(HttpService.JSONEncode, HttpService, Config)
		if ok then pcall(writefile, CONFIG_FILE, raw) end
	end)
end

loadConfig()

local state = {
	alive = true,
	connections = {},
	guiConnections = {},
	guiBuilding = false,
	screen = nil,
	window = nil,
	list = nil,
	status = nil,
	search = nil,
	tabButtons = {},
	originals = setmetatable({}, { __mode = "k" }),
	owned = setmetatable({}, { __mode = "k" }),
	animateBaseline = nil,
	currentCharacter = nil,
}

local function ensureLogs()
	pcall(function() if not isfolder("logs") then makefolder("logs") end end)
end

local function log(message)
	ensureLogs()
	local line = string.format("[%s] %s %s\n", os.date("%H:%M:%S"), BUILD_VERSION, tostring(message))
	pcall(function()
		if appendfile and isfile and isfile(LOG_FILE) then appendfile(LOG_FILE, line) else writefile(LOG_FILE, line) end
	end)
end

local function connect(signal, callback)
	local connection = signal:Connect(callback)
	local sink = state.guiBuilding and state.guiConnections or state.connections
	sink[#sink + 1] = connection
	return connection
end

local function stopAndDestroy(track)
	if not track then return end
	pcall(track.Stop, track, 0)
	pcall(track.Destroy, track)
end

local function resolveAnimation(character, slot)
	local animate = character and character:FindFirstChild("Animate")
	if not animate then return nil end
	local names = {
		idle1 = { "idle", "Animation1" }, idle2 = { "idle", "Animation2" },
		walk = { "walk", "WalkAnim" }, run = { "run", "RunAnim" },
		jump = { "jump", "JumpAnim" }, fall = { "fall", "FallAnim" },
		climb = { "climb", "ClimbAnim" }, swim = { "swim", "SwimIdleAnim" },
		swimidle = { "swimidle", "SwimIdleAnim" },
	}
	local path = names[slot]
	local folder = animate:FindFirstChild(path[1])
	local animation = folder and folder:FindFirstChild(path[2])
	return animation and animation:IsA("Animation") and animation or nil
end

local function restartStockAnimate(character, finalDisabled)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	local animate = character and character:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then animate.Disabled = true end
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do stopAndDestroy(track) end
	end
	if animate and animate:IsA("LocalScript") then
		task.defer(function() if animate.Parent then animate.Disabled = finalDisabled == true end end)
	end
end

local function applyResolved(reason)
	local character = localPlayer.Character
	if not character then log("apply failed: no character") return false end
	local animate = character:FindFirstChild("Animate")
	if state.animateBaseline == nil and animate and animate:IsA("LocalScript") then state.animateBaseline = animate.Disabled end
	restartStockAnimate(character, false)
	local changed = 0
	for _, slot in ipairs(SLOT_ORDER) do
		local source = Config.slotSources[slot] or Config.selectedPack
		local pack = PACK_BY_NAME[source]
		local asset = pack and pack.slots[slot]
		local animation = asset and resolveAnimation(character, slot)
		if animation then
			if state.originals[animation] == nil then state.originals[animation] = animation.AnimationId end
			local value = "rbxassetid://" .. tostring(asset)
			animation.AnimationId = value
			state.owned[animation] = value
			changed += 1
		end
	end
	state.currentCharacter = character
	log(string.format("apply reason=%s selected=%s slots=%d", tostring(reason), Config.selectedPack, changed))
	return changed > 0
end

local function applyPack(name)
	if not PACK_BY_NAME[name] then return end
	Config.selectedPack = name
	for _, slot in ipairs(SLOT_ORDER) do Config.slotSources[slot] = name end
	saveConfig()
	if Config.enabled then applyResolved("pack " .. name) end
end

local function restoreOriginals()
	local restored = 0
	if state.currentCharacter then restartStockAnimate(state.currentCharacter, state.animateBaseline) end
	for animation, original in next, state.originals do
		if animation.Parent and animation.AnimationId == state.owned[animation] then
			animation.AnimationId = original
			restored += 1
		end
	end
	log("restore originals=" .. tostring(restored))
end

--==========================================================================
-- Frontend -- R3ST Hub shell
--   Nothing below this line touches animation state. Every control calls one
--   of the four backend entry points above: applyPack, applyResolved,
--   restoreOriginals, saveConfig. Slot and pack semantics are unchanged.
--
--   hub.lua publishes getgenv().__R3ST_HOST immediately before running us.
--   When it is present the hub owns the ScreenGui, the window chrome, the drag
--   and the show/hide key, so we render into its content host and build none of
--   those four. Injected on our own, we build the window exactly as before.
--==========================================================================
local HOST = (type(G.__R3ST_HOST) == "table" and typeof(G.__R3ST_HOST.host) == "Instance") and G.__R3ST_HOST or nil

local function new(className, props, parent)
	local object = Instance.new(className)
	for key, value in next, props or {} do object[key] = value end
	object.Parent = parent
	return object
end

-- Same tokens as scripts/hub.lua, so an embedded page is indistinguishable
-- from the hub's own.
local COLORS = {
	bg = Color3.fromRGB(8, 9, 11), panel = Color3.fromRGB(13, 15, 17),
	card = Color3.fromRGB(20, 22, 25), card2 = Color3.fromRGB(29, 31, 35),
	line = Color3.fromRGB(45, 48, 53), text = Color3.fromRGB(238, 239, 241),
	muted = Color3.fromRGB(165, 167, 172), accent = Color3.fromRGB(250, 250, 250),
	black = Color3.fromRGB(8, 9, 11), green = Color3.fromRGB(72, 205, 57),
}

local function corner(object, radius)
	new("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, object)
end

local function stroke(object, color)
	new("UIStroke", { Color = color or COLORS.line, Thickness = 1, Transparency = 0 }, object)
end

local function makeButton(parent, text, size, position)
	local button = new("TextButton", {
		Text = text, Size = size, Position = position or UDim2.new(),
		BackgroundColor3 = COLORS.card2, TextColor3 = COLORS.text,
		Font = Enum.Font.GothamMedium, TextSize = 13, AutoButtonColor = false,
		BorderSizePixel = 0,
	}, parent)
	corner(button, 7)
	stroke(button)
	connect(button.MouseEnter, function() button.BackgroundColor3 = COLORS.line end)
	connect(button.MouseLeave, function() button.BackgroundColor3 = COLORS.card2 end)
	return button
end

local render
local function setStatus(text, good)
	if state.status then
		state.status.Text = text
		state.status.TextColor3 = good and COLORS.green or COLORS.muted
	end
end

local TABS = { "Custom", "Roblox", "UGC", "Slots" }
local function tabCount(tab)
	if tab == "Slots" then return #SLOT_ORDER end
	local n = 0
	for _, pack in ipairs(PACKS) do if pack.category == tab then n += 1 end end
	return n
end

-- Two columns wherever the host is wide enough; one when it is not.
local function columns()
	local w = state.list and state.list.AbsoluteSize.X or 700
	return w >= 640 and 2 or 1
end

local function place(index, height, cols)
	local col = (index - 1) % cols
	local row = math.floor((index - 1) / cols)
	local width = cols == 2 and UDim2.new(0.5, -9, 0, height) or UDim2.new(1, -12, 0, height)
	local x = cols == 2 and UDim2.new(col * 0.5, col == 0 and 6 or 3, 0, row * (height + 8) + 6)
		or UDim2.fromOffset(6, row * (height + 8) + 6)
	return width, x, row
end

local function buildPackCards(category)
	local query = state.search and string.lower(state.search.Text) or ""
	local cols = columns()
	local index, rows = 0, 0
	for _, pack in ipairs(PACKS) do
		if pack.category == category and (query == "" or string.lower(pack.name):find(query, 1, true)) then
			index += 1
			local active = pack.name == Config.selectedPack
			local size, pos, row = place(index, 62, cols)
			rows = row
			local card = new("Frame", {
				Size = size, Position = pos,
				BackgroundColor3 = active and COLORS.card2 or COLORS.card,
				BorderSizePixel = 0,
			}, state.list)
			corner(card, 8)
			stroke(card, active and COLORS.accent or COLORS.line)
			new("Frame", { Size = UDim2.new(0, 3, 1, -18), Position = UDim2.fromOffset(9, 9),
				BackgroundColor3 = active and COLORS.accent or COLORS.line, BorderSizePixel = 0 }, card)
			new("TextLabel", {
				Text = pack.name, Size = UDim2.new(1, -140, 0, 22), Position = UDim2.fromOffset(22, 9),
				BackgroundTransparency = 1, TextColor3 = COLORS.text, TextXAlignment = Enum.TextXAlignment.Left,
				Font = Enum.Font.GothamBold, TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd,
			}, card)
			new("TextLabel", {
				Text = pack.bundleId and ("bundle " .. tostring(pack.bundleId)) or "9 animation slots",
				Size = UDim2.new(1, -140, 0, 16), Position = UDim2.fromOffset(22, 33),
				BackgroundTransparency = 1, TextColor3 = COLORS.muted, TextXAlignment = Enum.TextXAlignment.Left,
				Font = Enum.Font.Gotham, TextSize = 11, TextTruncate = Enum.TextTruncate.AtEnd,
			}, card)
			local apply = makeButton(card, active and "active" or "apply", UDim2.fromOffset(96, 32), UDim2.new(1, -108, 0, 15))
			if active then
				apply.BackgroundColor3 = COLORS.accent
				apply.TextColor3 = COLORS.black
			end
			connect(apply.Activated, function()
				applyPack(pack.name)
				setStatus("applied " .. pack.name .. " to all 9 slots", true)
				render()
			end)
		end
	end
	if index == 0 then
		local empty = new("Frame", { Size = UDim2.new(1, -12, 0, 74), Position = UDim2.fromOffset(6, 6),
			BackgroundColor3 = COLORS.card, BorderSizePixel = 0 }, state.list)
		corner(empty, 8)
		stroke(empty)
		new("TextLabel", { Text = "No " .. category .. " pack matches that search",
			Size = UDim2.new(1, -32, 0, 24), Position = UDim2.fromOffset(16, 16), BackgroundTransparency = 1,
			TextColor3 = COLORS.text, TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamBold,
			TextSize = 13 }, empty)
		new("TextLabel", { Text = "Clear the box to see all " .. tostring(tabCount(category)) .. ".",
			Size = UDim2.new(1, -32, 0, 20), Position = UDim2.fromOffset(16, 42), BackgroundTransparency = 1,
			TextColor3 = COLORS.muted, TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamMedium,
			TextSize = 12 }, empty)
		rows = 0
		index = 1
	end
	state.list.CanvasSize = UDim2.fromOffset(0, (rows + 1) * 70 + 12)
end

local function cycleSource(slot, delta)
	local current = Config.slotSources[slot] or Config.selectedPack
	local index = 1
	for i, pack in ipairs(PACKS) do if pack.name == current then index = i break end end
	repeat
		index = ((index - 1 + delta) % #PACKS) + 1
	until PACKS[index].slots[slot]
	Config.slotSources[slot] = PACKS[index].name
	saveConfig()
	render()
end

local function buildSlots()
	local cols = columns()
	local rows = 0
	for i, slot in ipairs(SLOT_ORDER) do
		local source = Config.slotSources[slot] or Config.selectedPack
		local pack = PACK_BY_NAME[source]
		local asset = pack and pack.slots[slot] or "?"
		local size, pos, row = place(i, 54, cols)
		rows = row
		local rowFrame = new("Frame", { Size = size, Position = pos, BackgroundColor3 = COLORS.card, BorderSizePixel = 0 }, state.list)
		corner(rowFrame, 7)
		stroke(rowFrame)
		new("TextLabel", {
			Text = SLOT_LABEL[slot], Size = UDim2.fromOffset(84, 54), Position = UDim2.fromOffset(14, 0),
			BackgroundTransparency = 1, TextColor3 = COLORS.text, TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.GothamBold, TextSize = 12,
		}, rowFrame)
		local picker = makeButton(rowFrame, "  " .. source .. "   ·   " .. tostring(asset),
			UDim2.new(1, -112, 0, 36), UDim2.fromOffset(100, 9))
		picker.TextXAlignment = Enum.TextXAlignment.Left
		picker.TextTruncate = Enum.TextTruncate.AtEnd
		connect(picker.Activated, function() cycleSource(slot, 1) end)
		connect(picker.MouseButton2Click, function() cycleSource(slot, -1) end)
	end
	local y = (rows + 1) * 62 + 8
	new("TextLabel", { Text = "Left click a slot to step forward through the packs that define it, right click to step back.",
		Size = UDim2.new(1, -12, 0, 18), Position = UDim2.fromOffset(6, y), BackgroundTransparency = 1,
		TextColor3 = COLORS.muted, TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamMedium,
		TextSize = 11 }, state.list)
	local apply = makeButton(state.list, "apply this slot mix", UDim2.new(0.5, -9, 0, 38), UDim2.fromOffset(6, y + 24))
	apply.BackgroundColor3 = COLORS.accent
	apply.TextColor3 = COLORS.black
	connect(apply.Activated, function()
		saveConfig()
		applyResolved("slot mix")
		setStatus("applied custom slot mix", true)
	end)
	local all = makeButton(state.list, Config.selectedPack .. "  →  every slot", UDim2.new(0.5, -9, 0, 38), UDim2.new(0.5, 3, 0, y + 24))
	all.TextTruncate = Enum.TextTruncate.AtEnd
	connect(all.Activated, function()
		for _, slot in ipairs(SLOT_ORDER) do Config.slotSources[slot] = Config.selectedPack end
		saveConfig()
		render()
		setStatus("all slots point at " .. Config.selectedPack .. " — press apply to commit")
	end)
	state.list.CanvasSize = UDim2.fromOffset(0, y + 74)
end

render = function()
	if not state.alive or not state.list then return end
	local wasBuilding = state.guiBuilding
	state.guiBuilding = true
	for _, child in ipairs(state.list:GetChildren()) do child:Destroy() end
	if Config.activeTab == "Slots" then buildSlots() else buildPackCards(Config.activeTab) end
	if state.tabButtons then
		for name, tabButton in pairs(state.tabButtons) do
			local on = name == Config.activeTab
			tabButton.BackgroundColor3 = on and COLORS.accent or COLORS.card2
			tabButton.TextColor3 = on and COLORS.black or COLORS.text
		end
	end
	state.guiBuilding = wasBuilding
end

local function buildGui()
	state.guiBuilding = true
	local body   -- everything is laid out inside this, embedded or not
	if HOST then
		body = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0 }, HOST.host)
		-- destroy() tears down state.screen; embedded that is this frame, never
		-- the hub's host.
		state.screen = body
		state.window = body
	else
		local core = CoreGui
		if type(cloneref) == "function" then
			local ok, copy = pcall(cloneref, core)
			if ok and copy then core = copy end
		end
		local screen = new("ScreenGui", {
			Name = "Anims_" .. tostring(math.random(1000, 9999)), ResetOnSpawn = false,
			IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Global, DisplayOrder = 2147483647,
		}, nil)
		pcall(sethiddenproperty, screen, "OnTopOfCoreBlur", true)
		screen.Parent = core
		state.screen = screen

		local window = new("Frame", {
			Size = UDim2.fromOffset(820, 590), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(Config.windowX, Config.windowY), BackgroundColor3 = COLORS.bg,
			BorderSizePixel = 0, Visible = not Config.hidden,
		}, screen)
		state.window = window
		corner(window, 12)
		stroke(window)

		local header = new("Frame", { Size = UDim2.new(1, 0, 0, 60), BackgroundTransparency = 1 }, window)
		local logo = new("Frame", { Size = UDim2.fromOffset(26, 26), Position = UDim2.fromOffset(22, 17),
			BackgroundColor3 = COLORS.accent, BorderSizePixel = 0, Rotation = 14 }, header)
		corner(logo, 2)
		new("Frame", { Size = UDim2.fromOffset(8, 8), AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = COLORS.bg, BorderSizePixel = 0 }, logo)
		new("TextLabel", {
			Text = "R3ST HUB", Size = UDim2.fromOffset(160, 30), Position = UDim2.fromOffset(60, 15),
			BackgroundTransparency = 1, TextColor3 = COLORS.text, TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.GothamBold, TextSize = 18,
		}, header)
		new("TextLabel", {
			Text = "|   Anims", Size = UDim2.fromOffset(230, 30), Position = UDim2.fromOffset(176, 16),
			BackgroundTransparency = 1, TextColor3 = COLORS.muted, TextXAlignment = Enum.TextXAlignment.Left,
			Font = Enum.Font.GothamMedium, TextSize = 14,
		}, header)
		local close = makeButton(header, "×", UDim2.fromOffset(38, 32), UDim2.new(1, -50, 0, 14))
		close.TextSize = 24
		connect(close.Activated, function() G[GKEY].destroy() end)

		body = new("Frame", { Position = UDim2.fromOffset(12, 60), Size = UDim2.new(1, -24, 1, -72),
			BackgroundTransparency = 1, BorderSizePixel = 0 }, window)

		local dragging, dragStart, startPos = false, nil, nil
		connect(header.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = true dragStart = input.Position startPos = window.Position
			end
		end)
		connect(UserInputService.InputChanged, function(input)
			if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
				local delta = input.Position - dragStart
				window.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
			end
		end)
		connect(UserInputService.InputEnded, function(input)
			if dragging and input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = false
				Config.windowX = math.clamp((window.AbsolutePosition.X + window.AbsoluteSize.X * 0.5) / math.max(1, screen.AbsoluteSize.X), 0, 1)
				Config.windowY = math.clamp((window.AbsolutePosition.Y + window.AbsoluteSize.Y * 0.5) / math.max(1, screen.AbsoluteSize.Y), 0, 1)
				saveConfig()
			end
		end)
	end

	-- Category rail + search
	local tabBar = new("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1 }, body)
	state.tabButtons = {}
	for i, tab in ipairs(TABS) do
		local button = makeButton(tabBar, tab .. "  " .. tostring(tabCount(tab)),
			UDim2.fromOffset(132, 36), UDim2.fromOffset((i - 1) * 138, 0))
		state.tabButtons[tab] = button
		connect(button.Activated, function()
			Config.activeTab = tab
			saveConfig()
			if state.search then state.search.Visible = tab ~= "Slots" end
			render()
		end)
	end

	local search = new("TextBox", {
		PlaceholderText = "  search packs...", Text = "", ClearTextOnFocus = false,
		Size = UDim2.new(1, -566, 0, 36), Position = UDim2.new(0, 560, 0, 0),
		BackgroundColor3 = COLORS.bg, TextColor3 = COLORS.text, PlaceholderColor3 = COLORS.muted,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.Gotham, TextSize = 12, BorderSizePixel = 0,
	}, tabBar)
	corner(search, 7)
	stroke(search)
	state.search = search
	search.Visible = Config.activeTab ~= "Slots"
	local searchToken = 0
	connect(search:GetPropertyChangedSignal("Text"), function()
		searchToken += 1
		local token = searchToken
		task.delay(0.15, function() if token == searchToken and state.alive then render() end end)
	end)

	local list = new("ScrollingFrame", {
		Size = UDim2.new(1, 0, 1, -94), Position = UDim2.fromOffset(0, 46),
		BackgroundColor3 = COLORS.panel, BorderSizePixel = 0, ScrollBarThickness = 3,
		ScrollBarImageColor3 = COLORS.line, CanvasSize = UDim2.new(),
	}, body)
	corner(list, 9)
	stroke(list)
	state.list = list
	connect(list:GetPropertyChangedSignal("AbsoluteSize"), function()
		-- One or two columns depending on how wide the host actually is.
		task.defer(function() if state.alive then render() end end)
	end)

	local footer = new("Frame", { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.new(0, 0, 1, -40),
		BackgroundTransparency = 1 }, body)
	local status = new("TextLabel", {
		Text = "selected: " .. Config.selectedPack, Size = UDim2.new(1, -280, 1, 0),
		Position = UDim2.fromOffset(4, 0), BackgroundTransparency = 1,
		TextColor3 = COLORS.muted, TextXAlignment = Enum.TextXAlignment.Left,
		Font = Enum.Font.GothamMedium, TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd,
	}, footer)
	state.status = status
	local enabledButton = makeButton(footer, Config.enabled and "Anims: ON" or "Anims: OFF",
		UDim2.fromOffset(110, 34), UDim2.new(1, -374, 0, 3))
	local reapply = makeButton(footer, "re-apply", UDim2.fromOffset(100, 34), UDim2.new(1, -260, 0, 3))
	connect(enabledButton.Activated, function()
		Config.enabled = not Config.enabled
		saveConfig()
		if Config.enabled then
			applyResolved("enabled")
			setStatus("animations enabled: " .. Config.selectedPack, true)
		else
			restoreOriginals()
			setStatus("animations disabled; originals restored")
		end
		enabledButton.Text = Config.enabled and "Anims: ON" or "Anims: OFF"
		log("enabled=" .. tostring(Config.enabled))
	end)
	connect(reapply.Activated, function()
		if Config.enabled then
			applyResolved("manual re-apply")
			setStatus("re-applied " .. Config.selectedPack, true)
		else
			setStatus("Anims is OFF — enable it first")
		end
	end)
	local reset = makeButton(footer, "restore originals", UDim2.fromOffset(130, 34), UDim2.new(1, -132, 0, 3))
	connect(reset.Activated, function()
		restoreOriginals()
		setStatus("restored the character's original animations")
	end)

	render()
	state.guiBuilding = false
end

local function detach()
	for _, connection in ipairs(state.guiConnections) do pcall(function() connection:Disconnect() end) end
	state.guiConnections = {}
	if state.screen then pcall(function() state.screen:Destroy() end) end
	state.screen, state.window, state.list, state.status, state.search = nil, nil, nil, nil, nil
	state.tabButtons = {}
	log("panel detached (animations " .. (Config.enabled and "remain applied" or "remain off") .. ")")
end

local function mount(hostContract)
	detach()
	HOST = hostContract
	buildGui()
	if Config.enabled then applyResolved("panel remount verify") end
	log("panel mounted embedded=" .. tostring(HOST ~= nil))
	return true
end

local function setEnabled(on)
	Config.enabled = on and true or false
	saveConfig()
	if Config.enabled then applyResolved("enabled via API") else restoreOriginals() end
	log("enabled=" .. tostring(Config.enabled) .. " via API")
	return Config.enabled
end

local function destroy()
	if not state.alive then return end
	restoreOriginals()
	state.alive = false
	for _, connection in ipairs(state.connections) do pcall(function() connection:Disconnect() end) end
	detach()
	if G[GKEY] and G[GKEY].destroy == destroy then G[GKEY] = nil end
	log("unload")
end

G[GKEY] = {
	destroy = destroy, detach = detach, mount = mount, apply = applyPack,
	setEnabled = setEnabled, isEnabled = function() return Config.enabled end,
	build = BUILD_VERSION, embedded = HOST ~= nil,
}
buildGui()

connect(UserInputService.InputBegan, function(input, processed)
	if input.KeyCode == Enum.KeyCode.RightShift then
		-- Embedded, the hub's own RightShift hides the whole window; hiding our
		-- frame too would leave the tab blank when the hub comes back.
		if HOST then return end
		Config.hidden = not Config.hidden
		if state.window then state.window.Visible = not Config.hidden end
		saveConfig()
		log(Config.hidden and "gui hidden" or "gui shown")
		return
	end
	if processed then return end
	if input.KeyCode == Enum.KeyCode.K then
		destroy()
	end
end)

connect(localPlayer.CharacterAdded, function()
	task.wait(1)
	if state.alive then applyResolved("respawn resume") end
end)

task.defer(function()
	if Config.enabled then applyResolved("boot resume") end
	log(string.format("boot packs=%d selected=%s tab=%s embedded=%s enabled=%s",
		#PACKS, Config.selectedPack, Config.activeTab, tostring(HOST ~= nil), tostring(Config.enabled)))
end)
