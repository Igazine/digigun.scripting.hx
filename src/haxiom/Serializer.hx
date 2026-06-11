package haxiom;

import haxiom.AST.Expr;
import haxiom.VM.BytecodeChunk;
import haxiom.VM.DebugSymbol;
import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.io.BytesOutput;
import haxe.crypto.Adler32;

class Serializer {
    public static function serialize(expr:Expr):String {
        var s = new haxe.Serializer();
        s.useCache = true;
        s.useEnumIndex = true;
        s.serialize(expr);
        return s.toString();
    }

    public static function deserialize(str:String):Expr {
        var u = new haxe.Unserializer(str);
        return u.unserialize();
    }

    public static function serializeToBytes(expr:Expr):Bytes {
        var str = serialize(expr);
        return Bytes.ofString(str);
    }

    public static function deserializeFromBytes(bytes:Bytes):Expr {
        return deserialize(bytes.toString());
    }

    static function crypt(data:Bytes, key:HXBCKey):Bytes {
        if (key == null || !key.isValid()) return data;
        var keyHash = haxe.crypto.Sha1.make(Bytes.ofString(key.toString()));
        var keyLen = keyHash.length;
        var result = Bytes.alloc(data.length);
        var state = 0;
        for (i in 0...data.length) {
            var k = keyHash.get(i % keyLen);
            state = (state + k + i) % 256;
            result.set(i, data.get(i) ^ state);
        }
        return result;
    }

    public static function serializeBytecode(chunk:BytecodeChunk, ?key:HXBCKey):Bytes {
        var payloadOut = new BytesOutput();
        
        // 1. Build string pool for filenames and variable names
        var stringPool:Array<String> = [];
        var stringPoolMap = new Map<String, Int>();
        
        inline function addToStringPool(s:String):Int {
            if (s == null) return -1;
            if (stringPoolMap.exists(s)) return stringPoolMap.get(s);
            var idx = stringPool.length;
            stringPoolMap.set(s, idx);
            stringPool.push(s);
            return idx;
        }

        if (chunk.positions != null) {
            for (pos in chunk.positions) {
                if (pos != null && pos.file != null) {
                    addToStringPool(pos.file);
                }
            }
        }
        
        var debugSymbols = chunk.debugSymbols != null ? chunk.debugSymbols : [];
        for (sym in debugSymbols) {
            if (sym != null && sym.name != null) {
                addToStringPool(sym.name);
            }
        }
        
        // Write stringPool length and items
        payloadOut.writeInt32(stringPool.length);
        for (s in stringPool) {
            var sBytes = Bytes.ofString(s);
            payloadOut.writeInt32(sBytes.length);
            payloadOut.write(sBytes);
        }
        
        // 2. Write instructions
        var insts = chunk.instructions != null ? chunk.instructions : [];
        payloadOut.writeInt32(insts.length);
        for (inst in insts) {
            payloadOut.writeInt32(inst);
        }
        
        // 3. Write positions
        var positions = chunk.positions != null ? chunk.positions : [];
        payloadOut.writeInt32(positions.length);
        for (pos in positions) {
            if (pos == null) {
                payloadOut.writeInt32(0);
                payloadOut.writeInt32(0);
                payloadOut.writeInt32(-1);
            } else {
                payloadOut.writeInt32(pos.line);
                payloadOut.writeInt32(pos.col);
                var fileIdx = -1;
                if (pos.file != null) {
                    fileIdx = stringPoolMap.get(pos.file);
                }
                payloadOut.writeInt32(fileIdx);
            }
        }
        
        // 4. Write constants via Serializer
        var constsStr = haxe.Serializer.run(chunk.constants != null ? chunk.constants : []);
        var constsBytes = Bytes.ofString(constsStr);
        payloadOut.writeInt32(constsBytes.length);
        payloadOut.write(constsBytes);

        // 5. Write debug symbols
        payloadOut.writeInt32(debugSymbols.length);
        for (sym in debugSymbols) {
            var nameIdx = stringPoolMap.get(sym.name);
            payloadOut.writeInt32(nameIdx);
            payloadOut.writeInt32(sym.slot);
            payloadOut.writeInt32(sym.startIp);
            payloadOut.writeInt32(sym.endIp);
        }
        
        // Compute Adler32 checksum of the unencrypted payload bytes
        var payloadBytes = payloadOut.getBytes();
        var checksum = Adler32.make(payloadBytes);
        
        // Encrypt if key is provided
        var encrypted = false;
        if (key != null && key.isValid()) {
            payloadBytes = crypt(payloadBytes, key);
            encrypted = true;
        }

        // Assemble final output
        var headerOut = new BytesOutput();
        headerOut.writeString("HXBC");
        headerOut.writeByte(1); // Version 1
        
        // Flags byte: bit 0 = isAsync, bit 1 = isEncrypted
        var flags = (chunk.isAsync ? 1 : 0) | (encrypted ? 2 : 0);
        headerOut.writeByte(flags);
        
        headerOut.writeInt32(chunk.maxSlots);
        headerOut.writeInt32(checksum);
        headerOut.write(payloadBytes);
        
        return headerOut.getBytes();
    }

    public static function deserializeBytecode(bytes:Bytes, ?key:HXBCKey):BytecodeChunk {
        var input = new BytesInput(bytes);
        if (input.length < 14) {
            throw "Invalid bytecode: data too short";
        }
        
        var magic = input.readString(4);
        if (magic != "HXBC") {
            throw "Invalid bytecode magic header";
        }
        
        var version = input.readByte();
        if (version != 1) {
            throw 'Unsupported bytecode version $version';
        }
        
        var flags = input.readByte();
        var isAsync = (flags & 1) == 1;
        var isEncrypted = (flags & 2) == 2;
        var maxSlots = input.readInt32();
        var checksum = input.readInt32();
        
        if (isEncrypted && (key == null || !key.isValid())) {
            throw "Bytecode is encrypted and requires a key to load";
        }
        if (!isEncrypted && key != null && key.isValid()) {
            throw "Bytecode is not encrypted but a key was provided";
        }

        // Read payload
        var payloadBytes = input.read(input.length - 14);
        
        // Decrypt if encrypted
        if (isEncrypted) {
            payloadBytes = crypt(payloadBytes, key);
        }

        // Verify checksum of decrypted payload
        var computedChecksum = Adler32.make(payloadBytes);
        if (computedChecksum != checksum) {
            if (isEncrypted) {
                throw "Invalid encryption key or corrupted data";
            } else {
                throw "Bytecode checksum verification failed (data corrupted)";
            }
        }
        
        var payloadInput = new BytesInput(payloadBytes);
        
        // 1. Read string pool
        var stringPoolLength = payloadInput.readInt32();
        var stringPool = [for (i in 0...stringPoolLength) {
            var len = payloadInput.readInt32();
            payloadInput.readString(len);
        }];
        
        // 2. Read instructions
        var instsLength = payloadInput.readInt32();
        var instructions = [for (i in 0...instsLength) payloadInput.readInt32()];
        
        // 3. Read positions
        var posLength = payloadInput.readInt32();
        var positions = [for (i in 0...posLength) {
            var line = payloadInput.readInt32();
            var col = payloadInput.readInt32();
            var fileIdx = payloadInput.readInt32();
            var file = (fileIdx >= 0 && fileIdx < stringPool.length) ? stringPool[fileIdx] : null;
            var pos:haxiom.AST.Pos = { line: line, col: col, file: file };
            pos;
        }];
        
        // 4. Read constants
        var constsLen = payloadInput.readInt32();
        var constsStr = payloadInput.readString(constsLen);
        var constants:Array<Dynamic> = haxe.Unserializer.run(constsStr);
        
        // 5. Read debug symbols
        var debugSymLength = payloadInput.readInt32();
        var debugSymbols:Array<DebugSymbol> = null;
        if (debugSymLength > 0) {
            debugSymbols = [for (i in 0...debugSymLength) {
                var nameIdx = payloadInput.readInt32();
                var slot = payloadInput.readInt32();
                var startIp = payloadInput.readInt32();
                var endIp = payloadInput.readInt32();
                var name = (nameIdx >= 0 && nameIdx < stringPool.length) ? stringPool[nameIdx] : "";
                var sym:DebugSymbol = { name: name, slot: slot, startIp: startIp, endIp: endIp };
                sym;
            }];
        }

        var chunk = new BytecodeChunk(instructions, constants, positions, maxSlots, isAsync, debugSymbols);
        BytecodeVerifier.verify(chunk);
        return chunk;
    }
}
