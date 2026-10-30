#ifndef CGS_PRIVATE_H
#define CGS_PRIVATE_H

#include <CoreFoundation/CoreFoundation.h>

//#region SkyLight 비공개 API 선언 (Spaces 조회용)
typedef int CGSConnectionID;
typedef uint64_t CGSSpaceID;

extern CGSConnectionID CGSMainConnectionID(void);
extern CGSSpaceID CGSGetActiveSpace(CGSConnectionID cid);
extern CFArrayRef CGSCopyManagedDisplaySpaces(CGSConnectionID cid);
//#endregion

//#region Dock 알림 (Mission Control.app 이 내부적으로 쓰는 방식)
// "com.apple.expose.awake" = Mission Control, "com.apple.showdesktop.awake" = 데스크탑 보기
extern void CoreDockSendNotification(CFStringRef notification, int unknown);
//#endregion

#endif
