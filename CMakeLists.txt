cmake_minimum_required(VERSION 3.21)

project(qtSIFIDS VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(QT_SKIP_AUTO_PLUGIN_INCLUSION ON)

find_package(Qt6 6.11 REQUIRED COMPONENTS
    Core
    Gui
    Location
    Multimedia
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

set(SIFIDS_APP_ICONS)
if(WIN32)
    # The .rc file embeds the icon in the .exe.
    file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/app_icon.rc
        "IDI_ICON1 ICON \"${CMAKE_CURRENT_SOURCE_DIR}/icons/ic_launcher.ico\"\n")
    set(SIFIDS_APP_ICONS ${CMAKE_CURRENT_BINARY_DIR}/app_icon.rc)
elseif(APPLE AND NOT IOS)
    set(SIFIDS_APP_ICONS ${CMAKE_CURRENT_SOURCE_DIR}/icons/ic_launcher.icns)
    set_source_files_properties(${SIFIDS_APP_ICONS} PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
endif()

qt_add_executable(qtSIFIDS
    src/main.cpp
    ${SIFIDS_APP_ICONS}
)

if(APPLE AND NOT IOS)
    set_target_properties(qtSIFIDS PROPERTIES
        MACOSX_BUNDLE_ICON_FILE ic_launcher.icns)
endif()

qt_add_qml_module(qtSIFIDS
    URI Sifids
    VERSION 1.0
    QML_FILES
        Main.qml
        qml/DateTimePickerDialog.qml
        qml/PlaceSelector.qml
    RESOURCES
        sounds/claxon.wav
        sounds/gps-warning.wav
    SOURCES
    src/AlarmAudio.cpp
    src/AlarmAudio.h
    src/AppStore.cpp
    src/AppStore.h
    src/LocationTracker.cpp
    src/LocationTracker.h
    src/SailPlan.cpp
    src/SailPlan.h
    src/ShareService.cpp
    src/ShareService.h
)

if(IOS)
    # ShareService.cpp delegates to this Objective-C++ UIActivityViewController
    # presenter on iOS; see ShareService_ios.mm for details.
    target_sources(qtSIFIDS PRIVATE src/ShareService_ios.mm)
    target_link_libraries(qtSIFIDS PRIVATE "-framework UIKit")
endif()

qt_add_resources(qtSIFIDS app_icon
    PREFIX /
    FILES icons/ic_launcher.png
)

target_include_directories(qtSIFIDS PRIVATE src)

if(ANDROID)
    # Qt's OpenSSL TLS backend needs these libraries bundled for https (map tiles, uploads).
    if(NOT ANDROID_SDK_ROOT AND DEFINED ENV{ANDROID_SDK_ROOT})
        set(ANDROID_SDK_ROOT $ENV{ANDROID_SDK_ROOT})
    endif()
    # Use a 16 KB page-aligned android_openssl checkout (https://github.com/KDAB/android_openssl);
    # the copy bundled with older SDK installs is only 4 KB aligned.
    set(SIFIDS_ANDROID_OPENSSL_ROOT "${ANDROID_SDK_ROOT}/android_openssl" CACHE PATH
        "android_openssl directory containing ssl_3/<abi>")
    set(SIFIDS_ANDROID_OPENSSL ${SIFIDS_ANDROID_OPENSSL_ROOT}/ssl_3/${CMAKE_ANDROID_ARCH_ABI})
    if(EXISTS ${SIFIDS_ANDROID_OPENSSL}/libssl_3.so)
        set_property(TARGET qtSIFIDS APPEND PROPERTY QT_ANDROID_EXTRA_LIBS
            ${SIFIDS_ANDROID_OPENSSL}/libcrypto_3.so
            ${SIFIDS_ANDROID_OPENSSL}/libssl_3.so)
    else()
        message(WARNING "android_openssl not found at ${SIFIDS_ANDROID_OPENSSL}; https will not work")
    endif()

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
    Qt6::Multimedia
    Qt6::Network
    Qt6::Positioning
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::QuickDialogs2
    Qt6::Sql
)

if(TARGET Qt6::QFFmpegMediaPlugin)
    qt_import_plugins(qtSIFIDS INCLUDE Qt6::QFFmpegMediaPlugin)
endif()

option(SIFIDS_VESSEL_SIMULATOR "Enable the debug vessel simulator" ON)
if(SIFIDS_VESSEL_SIMULATOR AND NOT CMAKE_BUILD_TYPE MATCHES "^(Release|MinSizeRel)$")
    target_compile_definitions(qtSIFIDS PRIVATE SIFIDS_VESSEL_SIMULATOR)
endif()

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

    qt_add_executable(qtSIFIDS_sailplan_tests
        tests/SailPlanTests.cpp
        src/SailPlan.cpp
        src/SailPlan.h
    )
    target_include_directories(qtSIFIDS_sailplan_tests PRIVATE src)
    target_link_libraries(qtSIFIDS_sailplan_tests PRIVATE
        Qt6::Core
        Qt6::Qml
        Qt6::Test
    )
    add_test(NAME qtSIFIDS_sailplan_tests COMMAND qtSIFIDS_sailplan_tests)
endif()
