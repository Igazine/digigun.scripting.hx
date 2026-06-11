package haxiom;

import haxiom.AST.Expr;
import haxiom.VM.BytecodeChunk;
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

    public static function serializeBytecode(chunk:BytecodeChunk):Bytes {
        var payloadOut = new BytesOutput();
        
        // 1. Build string pool for filenames in positions
        var filePool:Array<String> = [];
        var filePoolMap = new Map<String, Int>();
        if (chunk.positions != null) {
            for (pos in chunk.positions) {
                if (pos != null && pos.file != null) {
                    if (!filePoolMap.exists(pos.file)) {
                        filePoolMap.set(pos.file, filePool.length);
                        filePool.push(pos.file);
                    }
                }
            }
        }
        
        // Write filePool length and items
        payloadOut.writeInt32(filePool.length);
        for (f in filePool) {
            var fBytes = Bytes.ofString(f);
            payloadOut.writeInt32(fBytes.length);
            payloadOut.write(fBytes);
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
                    fileIdx = filePoolMap.get(pos.file);
                }
                payloadOut.writeInt32(fileIdx);
            }
        }
        
        // 4. Write constants via Serializer
        var constsStr = haxe.Serializer.run(chunk.constants != null ? chunk.constants : []);
        var constsBytes = Bytes.ofString(constsStr);
        payloadOut.writeInt32(constsBytes.length);
        payloadOut.write(constsBytes);
        
        // Compute Adler32 checksum of the payload bytes
        var payloadBytes = payloadOut.getBytes();
        var checksum = Adler32.make(payloadBytes);
        
        // Assemble final output
        var headerOut = new BytesOutput();
        headerOut.writeString("HXBC");
        headerOut.writeByte(1); // Version 1
        headerOut.writeByte(chunk.isAsync ? 1 : 0);
        headerOut.writeInt32(chunk.maxSlots);
        headerOut.writeInt32(checksum);
        headerOut.write(payloadBytes);
        
        return headerOut.getBytes();
    }

    public static function deserializeBytecode(bytes:Bytes):BytecodeChunk {
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
        
        var isAsync = input.readByte() == 1;
        var maxSlots = input.readInt32();
        var checksum = input.readInt32();
        
        // Read payload
        var payloadBytes = input.read(input.length - 14);
        
        // Verify checksum
        var computedChecksum = Adler32.make(payloadBytes);
        if (computedChecksum != checksum) {
            throw "Bytecode checksum verification failed (data corrupted)";
        }
        
        var payloadInput = new BytesInput(payloadBytes);
        
        // 1. Read file pool
        var filePoolLength = payloadInput.readInt32();
        var filePool = [for (i in 0...filePoolLength) {
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
            var file = (fileIdx >= 0 && fileIdx < filePool.length) ? filePool[fileIdx] : null;
            var pos:haxiom.AST.Pos = { line: line, col: col, file: file };
            pos;
        }];
        
        // 4. Read constants
        var constsLen = payloadInput.readInt32();
        var constsStr = payloadInput.readString(constsLen);
        var constants:Array<Dynamic> = haxe.Unserializer.run(constsStr);
        
        var chunk = new BytecodeChunk(instructions, constants, positions, maxSlots, isAsync);
        BytecodeVerifier.verify(chunk);
        return chunk;
    }
}
