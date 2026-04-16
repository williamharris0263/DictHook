#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonCryptor.h>
#import "fishhook.h"

// ==========================================
// 辅助工具函数
// ==========================================
// 1. 获取 SQLite 数据库文件名
const char *sqlite3_db_filename(void *db, const char *zDbName);

// 2. 将字节转为 Hex 字符串
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
// 守卫一：数据库密码拦截 (SQLCipher)
// ==========================================
static NSMutableArray *allCapturedDbKeys;
static int (*original_sqlite3_key)(void *db, const void *pKey, int nKey);

static int replaced_sqlite3_key(void *db, const void *pKey, int nKey) {
    if (nKey > 0 && pKey != NULL) {
        if (!allCapturedDbKeys) allCapturedDbKeys = [[NSMutableArray alloc] init];
        
        NSData *keyData = [NSData dataWithBytes:pKey length:nKey];
        NSString *keyString = [[NSString alloc] initWithData:keyData encoding:NSUTF8StringEncoding];
        
        NSString *dbPathStr = @"[未知数据库路径]";
        const char *dbPath = sqlite3_db_filename(db, "main");
        if (dbPath != NULL) dbPathStr = [NSString stringWithUTF8String:dbPath];
        
        NSString *msg = [NSString stringWithFormat:@"📂 数据库: %@\n🔑 明文: %@\n🧬 Hex: %@", 
                        dbPathStr.lastPathComponent ?: dbPathStr, keyString ?: @"[无法转码]", keyData];
        
        if (![allCapturedDbKeys containsObject:msg]) {
            [allCapturedDbKeys addObject:msg];
            NSString *finalOutput = [allCapturedDbKeys componentsJoinedByString:@"\n----------------------\n"];
            
            // 静默写入文件
            NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
            [finalOutput writeToFile:[docPath stringByAppendingPathComponent:@"sqlcipher_all_keys.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
            
            // 顺手复制到剪贴板
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
        
        // 覆盖剪贴板为网页密钥
        dispatch_async(dispatch_get_main_queue(), ^{
            [UIPasteboard generalPasteboard].string = msg;
        });
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
    
    // 2. 延迟 5 秒的安全引导弹窗
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        UIViewController *topVC = keyWindow.rootViewController;
        while (topVC.presentedViewController) {
            topVC = topVC.presentedViewController;
        }
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🛡️ 全能提取器已就绪" 
                                                                       message:@"1. 数据库密码已在后台静默收集。\n2. 网页解密蹲守中，请随便点击一个词条。\n\n收集到的所有数据均存放在 App 沙盒 Documents 目录下（sqlcipher_all_keys.txt 和 CCCrypt_Key.txt），您也可尝试去备忘录粘贴查看最近的一条。" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"开始提取" style:UIAlertActionStyleDefault handler:nil]];
        if (topVC) {
            [topVC presentViewController:alert animated:YES completion:nil];
        }
    });
}
