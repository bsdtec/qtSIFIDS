cmake_minimum_required(VERSION 3.21)

project(qtSIFIDS VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(QT_SKIP_AUTO_PLUGIN_INCLUSION ON)

find_package(Qt6 6.11 REQUIRED COMPONENTS
    Core
    Gui
    Location
    Network
    Positioning
    Qml
    Quick
    QuickControls2
    QuickDialogs2
    Sql
)

qt_standard_project_setup()
qt_policy(SET QTP0001 NEW)
qt_policy(SET QTP0004 NEW)

qt_add_executable(qtSIFIDS
    src/main.cpp
)

qt_add_qml_module(qtSIFIDS
    URI Sifids
    VERSION 1.0
    QML_FILES
        Main.qml
    SOURCES
    src/AppStore.cpp
    src/AppStore.h
    src/LocationTracker.cpp
    src/LocationTracker.h
)

target_include_directories(qtSIFIDS PRIVATE src)

if(ANDROID)
    set_target_properties(qtSIFIDS PROPERTIES
        QT_ANDROID_PACKAGE_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/android
        QT_ANDROID_VERSION_NAME ${PROJECT_VERSION}
        QT_ANDROID_VERSION_CODE 1
        QT_ANDROID_MIN_SDK_VERSION 28
        QT_ANDROID_TARGET_SDK_VERSION 35
    )
endif()

target_link_libraries(qtSIFIDS PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Location
    Qt6::Network
    Qt6::Positioning
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::QuickDialogs2
    Qt6::Sql
)

include(GNUInstallDirs)
install(TARGETS qtSIFIDS
    BUNDLE DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
)

include(CTest)
if(BUILD_TESTING)
    find_package(Qt6 6.11 REQUIRED COMPONENTS Test)
    qt_add_executable(qtSIFIDS_tests
        tests/AppStoreTests.cpp
        src/AppStore.cpp
        src/AppStore.h
    )
    target_include_directories(qtSIFIDS_tests PRIVATE src)
    target_link_libraries(qtSIFIDS_tests PRIVATE
        Qt6::Core
        Qt6::Network
        Qt6::Positioning
        Qt6::Qml
        Qt6::Sql
        Qt6::Test
    )
    add_test(NAME qtSIFIDS_tests COMMAND qtSIFIDS_tests)
endif()
