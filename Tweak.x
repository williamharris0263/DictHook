#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonCryptor.h>
#import <dlfcn.h>
#import "fishhook.h"

// ==========================================
// 辅助工具函数
// ==========================================
static NSString * hexStringFromData(const void *bytes, size_t length) {
    if (bytes == NULL || length == 0) return @"";
    NSMutableString *hexStr = [NSMutableString stringWithCapacity:length * 2];
    const unsigned char *buf = (const unsigned char *)bytes;
    for (int i = 0; i < length; ++i) {
        [hexStr appendFormat:@"%02X", (unsigned int)buf[i]];
    }
    return hexStr;
}

// ==========================================
// 守卫一：数据库密码全量拦截 (永远保留该功能！)
// ==========================================
static NSMutableArray *allCapturedDbKeys; // 全局数组，保存所有密码
static int (*original_sqlite3_key)(void *db, const void *pKey, int nKey);

static int replaced_sqlite3_key(void *db, const void *pKey, int nKey) {
    if (nKey > 0 && pKey != NULL) {
        if (!allCapturedDbKeys) allCapturedDbKeys = [[NSMutableArray alloc] init];
        
        NSData *keyData = [NSData dataWithBytes:pKey length:nKey];
        // 核心诉求：抓取明文密码
        NSString *keyString = [[NSString alloc] initWithData:keyData encoding:NSUTF8StringEncoding];
        
        NSString *dbPathStr = @"[未知数据库路径]";
        
        // 动态反查数据库文件名，避免链接报错
        const char *(*dynamic_sqlite3_db_filename)(void *, const char *) = dlsym(RTLD_DEFAULT, "sqlite3_db_filename");
        if (dynamic_sqlite3_db_filename != NULL) {
            const char *dbPath = dynamic_sqlite3_db_filename(db, "main");
            if (dbPath != NULL) {
                dbPathStr = [NSString stringWithUTF8String:dbPath];
            }
        }
        
        NSString *msg = [NSString stringWithFormat:@"📂 数据库: %@\n🔑 明文: %@\n🧬 Hex: %@", 
                        dbPathStr.lastPathComponent ?: dbPathStr, keyString ?: @"[无法转码为普通文本]", keyData];
        
        // 追加写入，获取全部密码
        if (![allCapturedDbKeys containsObject:msg]) {
            [allCapturedDbKeys addObject:msg];
            NSString *finalOutput = [allCapturedDbKeys componentsJoinedByString:@"\n----------------------\n"];
            
            // 写入沙盒
            NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            [finalOutput writeToFile:[docPath stringByAppendingPathComponent:@"sqlcipher_all_keys.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            
            // 写入剪贴板
            dispatch_async(dispatch_get_main_queue(), ^{
                [UIPasteboard generalPasteboard].string = finalOutput;
            });
        }
    }
    return original_sqlite3_key(db, pKey, nKey);
}

// ==========================================
// 守卫二：网页解密拦截 (CCCrypt)
// ==========================================
static BOOL hasGrabbedCCCryptKey = NO;
static int (*original_CCCrypt)(CCOperation op, CCAlgorithm alg, CCOptions options,
                               const void *key, size_t keyLength, const void *iv,
                               const void *dataIn, size_t dataInLength,
                               void *dataOut, size_t dataOutAvailable, size_t *dataOutMoved);

static int replaced_CCCrypt(CCOperation op, CCAlgorithm alg, CCOptions options,
                            const void *key, size_t keyLength, const void *iv,
                            const void *dataIn, size_t dataInLength,
                            void *dataOut, size_t dataOutAvailable, size_t *dataOutMoved) {
    
    if (op == kCCDecrypt && !hasGrabbedCCCryptKey) {
        hasGrabbedCCCryptKey = YES; 
        
        NSString *hexKey = hexStringFromData(key, keyLength);
        NSString *hexIV = iv ? hexStringFromData(iv, 16) : @"无 (None)"; 
        NSString *algoName = (alg == kCCAlgorithmAES128) ? @"AES-128" : @"DES/其他";
        
        NSString *msg = [NSString stringWithFormat:@"[网页 CCCrypt 解密密钥]\n算法: %@\nHex Key: %@\nHex IV: %@", algoName, hexKey, hexIV];
        
        NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        [msg writeToFile:[docPath stringByAppendingPathComponent:@"CCCrypt_Key.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    return original_CCCrypt(op, alg, options, key, keyLength, iv, dataIn, dataInLength, dataOut, dataOutAvailable, dataOutMoved);
}

// ==========================================
// 初始化注入
// ==========================================
%ctor {
    // 1. 同时挂载两个 Hook
    struct rebinding rebs[2];
    rebs[0].name = "sqlite3_key";
    rebs[0].replacement = (void *)replaced_sqlite3_key;
    rebs[0].replaced = (void **)&original_sqlite3_key;
    
    rebs[1].name = "CCCrypt";
    rebs[1].replacement = (void *)replaced_CCCrypt;
    rebs[1].replaced = (void **)&original_CCCrypt;
    
    rebind_symbols(rebs, 2);
    
    // 2. 延迟 10 秒的安全汇报
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        UIViewController *topVC = keyWindow.rootViewController;
        while (topVC.presentedViewController) {
            topVC = topVC.presentedViewController;
        }
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🛡️ 全能提取器已就绪" 
                                                                       message:@"1. 所有数据库密码（含明文）已在后台静默全量收集。\n2. 网页解密同步蹲守中。\n\n请在沙盒 Documents 目录下查看结果，或在备忘录中粘贴。" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"开始提取" style:UIAlertActionStyleDefault handler:nil]];
        if (topVC) {
            [topVC presentViewController:alert animated:YES completion:nil];
        }
    });
}
