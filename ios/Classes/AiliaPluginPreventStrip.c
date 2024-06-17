//
//  AiliPluginPreventStrip.c
//
//  Created by Kazuki Kyakuno on 2023/07/31.
//

// Dummy link to keep libailia.a from being deleted

extern const char* ailiaGetErrorDetail(void* net);

void test(void){
    ailiaGetErrorDetail(0);
}
