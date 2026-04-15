#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "fishhook.h"  // 引入 fishhook

// 1. 定义原函数指针
static int (*original_sqlite3_key)(void *db, const void *pKey, int nKey);

// 2. 我们的拦截函数
static int replaced_sqlite3_key(void *db, const void *pKey, int nKey) {
    if (nKey > 0 && pKey != NULL) {
        NSData *keyData = [NSData dataWithBytes:pKey length:nKey];
        NSString *keyString = [[NSString alloc] initWithData:keyData encoding:NSUTF8StringEncoding];
        
        NSString *msg = [NSString stringWithFormat:@"[Fishhook 成功]\n明文密码:\n%@\n\nHex格式:\n%@", 
                        keyString ?: @"无法转为普通文本", keyData];
        
        // 复制到剪贴板
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIPasteboard generalPasteboard].string = msg;
        });
        
        // 写入沙盒备份
        NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *filePath = [docPath stringByAppendingPathComponent:@"sqlcipher_password.txt"];
        [msg writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    
    // 放行原函数，保证 App 正常运转
    return original_sqlite3_key(db, pKey, nKey);
}

// 3. 在插件加载时，安全的替换符号
%ctor {
    struct rebinding sql_hook;
    sql_hook.name = "sqlite3_key";
    sql_hook.replacement = (void *)replaced_sqlite3_key;
    sql_hook.replaced = (void **)&original_sqlite3_key;
    
    struct rebinding rebs[] = {sql_hook};
    rebind_symbols(rebs, 1);
}
