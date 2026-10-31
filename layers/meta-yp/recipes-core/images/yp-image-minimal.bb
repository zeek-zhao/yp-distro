SUMMARY = "YP minimal image —— 启动时间下限基准"
DESCRIPTION = "裸底（core-image-minimal）+ 品牌文件。不放业务、不放调试工具：\
这一层回答的是「这个发行版最快能多快起来」。"

require recipes-core/images/core-image-minimal.bb
include yp-image.inc
