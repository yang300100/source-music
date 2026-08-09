cmake_minimum_required(VERSION 3.5.0)
project(audio_eq_bridge)

set(NATIVE_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

include_directories(${NATIVE_ROOT_PATH})

add_library(audio_eq_bridge SHARED
            audio_eq_engine.cpp
            native_eq_player.cpp
            napi_init.cpp)

target_link_libraries(audio_eq_bridge PUBLIC
                      libace_napi.z.so
                      libnative_media_codecbase.so
                      libnative_media_core.so
                      libnative_media_acodec.so
                      libnative_media_avdemuxer.so
                      libnative_media_avsource.so
                      libohaudio.so
                      libohaudiosuite.so)
