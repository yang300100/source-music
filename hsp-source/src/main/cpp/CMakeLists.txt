cmake_minimum_required(VERSION 3.5.0)
project(jsvm_bridge)

# 设置 native 源码路径
set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

# 编译 jsvm_bridge 动态库（NAPI 模块名与库名一致）
add_library(jsvm_bridge SHARED
            jsvm_bridge.cpp
            napi_init.cpp)

# 链接鸿蒙基础库和 JSVM 引擎库
target_link_libraries(jsvm_bridge PUBLIC
                      libace_napi.z.so
                      libjsvm.so)

# 独立 QuickJS 解释器：不使用 JIT/可执行内存权限，每个音源拥有独立 Context。
add_library(quickjs_bridge SHARED
            quickjs_bridge.cpp
            quickjs_napi_init.cpp
            quickjs/quickjs.c
            quickjs/dtoa.c
            quickjs/libregexp.c
            quickjs/libunicode.c
            quickjs/cutils.c)

target_compile_definitions(quickjs_bridge PRIVATE
                           _GNU_SOURCE
                           CONFIG_VERSION="2026-06-04")
target_link_libraries(quickjs_bridge PUBLIC
                      libace_napi.z.so
                      libohcrypto.so
                      libm.so
                      libdl.so)
