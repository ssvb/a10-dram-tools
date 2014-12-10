cmake_minimum_required(VERSION 2.8)

project(a10-dram-tools C)
find_package(Threads REQUIRED)
set(CMAKE_C_FLAGS "-O2")

add_executable(a10-meminfo a10-meminfo.c)
add_executable(a10-set-tpr3 a10-set-tpr3.c)
add_executable(a10-stdin-watchdog a10-stdin-watchdog.c)
target_link_libraries(a10-stdin-watchdog ${CMAKE_THREAD_LIBS_INIT})

install_programs(/bin FILES a10-tpr3-scan a10-tpr3-html-report
                            a10-meminfo a10-set-tpr3 a10-stdin-watchdog
                            a10-dram-timings-calculator)
install_files(/bin FILES a10-tpr3-common.rb a10-dram-info.rb)
