#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <substrate.h>

// 1. 定义原函数指针
static int (*original_sqlite3_key)(void *db, const void *pKey, int nKey);

// 2. 我们的替换函数
static int replaced_sqlite3_key(void *db, const void *pKey, int nKey) {
    if (nKey > 0 && pKey != NULL) {
        NSData *keyData = [NSData dataWithBytes:pKey length:nKey];
        NSString *keyString = [[NSString alloc] initWithData:keyData encoding:NSUTF8StringEncoding];
        
        NSString *msg = [NSString stringWithFormat:@"抓到数据库密码了！\n明文密码:\n%@\n\nHex格式:\n%@", 
                        keyString ?: @"[无法转为普通文本]", keyData];
        
        // 动作A：静默复制到手机剪贴板 (放到主线程绝对安全)
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIPasteboard generalPasteboard].string = msg;
        });
        
        // 动作B：写入到 App 的 Documents 目录下备份
        NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        NSString *filePath = [docPath stringByAppendingPathComponent:@"sqlcipher_password.txt"];
        [msg writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    
    // 3. 必须放行原函数，否则 App 无法解密数据
    return original_sqlite3_key(db, pKey, nKey);
}

// 4. 构造函数：在 Tweak 加载时自动执行
%ctor {
    // 使用 dlsym 动态查找函数内存地址，绝不会引发启动闪退
    void *symbol = dlsym(RTLD_DEFAULT, "sqlite3_key");
    if (symbol != NULL) {
        MSHookFunction(symbol, (void *)replaced_sqlite3_key, (void **)&original_sqlite3_key);
    }
}
