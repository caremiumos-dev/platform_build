# Minimal product: build only framework/services/framework-res + boot jars.
PRODUCT_NAME := caremium_framework
PRODUCT_DEVICE := generic
PRODUCT_BRAND := generic

# Boot classpath jars (order matters)
PRODUCT_BOOT_JARS := \
    core-oj \
    core-libart \
    conscrypt \
    bouncycastle \
    apache-xml \
    ext \
    framework \
    telephony-common \
    voip-common \
    ims-common \
    org.apache.http.legacy.boot \
    android.hidl.base-V1.0-java \
    android.hidl.manager-V1.0-java

PRODUCT_SYSTEM_SERVER_JARS := \
    services \
    ethernet-service \
    wifi-service \
    com.android.location.provider

PRODUCT_PACKAGES += \
    framework \
    framework-res \
    services \
    telephony-common \
    wifi-service \
    voip-common \
    ims-common \
    core-libart \
    core-oj \
    ext \
    conscrypt \
    bouncycastle \
    apache-xml \
    org.apache.http.legacy.boot

TARGET_CORE_JARS := \
    core-oj \
    core-libart \
    conscrypt \
    bouncycastle \
    apache-xml \
    ext \
    framework \
    telephony-common \
    voip-common \
    ims-common \
    org.apache.http.legacy.boot

# default props
PRODUCT_DEFAULT_PROPERTY_OVERRIDES += \
    ro.zygote=zygote32

# no apps
PRODUCT_ENFORCE_RRO_TARGETS :=
