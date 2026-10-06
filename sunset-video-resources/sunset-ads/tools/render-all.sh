#!/bin/zsh
# Render every piece at print resolution into print/. PORT = the preview server's port.
cd "${0:a:h}/.."
R() { node tools/render.mjs "$1" "print/$2" "$3" ${4:-} | grep -v '^$'; }
sysctl -n vm.loadavg
R "billboard.html" billboard_10920x3640mm_1-10scale_300dpi.png 300 2400
for side in en jp; do
  R "meishi.html?side=$side" meishi_${side}_91x55mm_600dpi.png 600 1600
  for pl in sumi verm fount blind; do R "meishi.html?side=$side&plate=$pl" plates/meishi_${side}_plate-${pl}_600dpi.png 600; done
done
R "tee.html?part=back" tee_back_on-indigo_300dpi.png 300 1400
R "tee.html?part=back&garment=0" tee_back_film_300dpi.png 300
R "tee.html?part=chest" tee_chest_on-indigo_300dpi.png 300 1000
R "tee.html?part=chest&garment=0" tee_chest_film_300dpi.png 300
for pl in cream gold orange coral rose plum verm; do R "tee.html?part=back&plate=$pl" plates/tee_back_screen-${pl}_300dpi.png 300; done
for pl in cream gold orange verm; do R "tee.html?part=chest&plate=$pl" plates/tee_chest_screen-${pl}_300dpi.png 300; done
for n in 1 2 3; do R "b0.html?n=$n" b0_${n}_1030x1456mm_150dpi.png 150 1800; done
for k in 1 2 3 4 5; do R "corridor.html?sheet=$k" corridor_sheet${k}_B0_150dpi.png 150 1200; done
R "corridor.html" corridor_5150x1456mm_preview_40dpi.png 40 4000
echo ALL DONE
