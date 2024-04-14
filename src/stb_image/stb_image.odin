package stb_image
import "core:intrinsics"
import "core:mem"
import "core:math"

/*#ifdef STBI_NO_FAILURE_STRINGS
   #define stbi__err(x,y)  0
#elif defined(STBI_FAILURE_USERMSG)
   #define stbi__err(x,y)  stbi__err(y)
#else
   #define stbi__err(x,y)  stbi__err(x)
#endif*/

//#define stbi__errpf(x,y)   ((float *)(size_t) (stbi__err(x,y)?nil:nil))
//#define stbi__errpuc(x,y)  ((unsigned char *)(size_t) (stbi__err(x,y)?nil:nil))

stbi_error_msg1, stbi_error_msg2: string;

stbi__err :: proc(msg1, msg2: string) -> bool {
	// TODO: Set error msg
	stbi_error_msg1, stbi_error_msg2 = msg1, msg2;
	return false;
}

stbi__errpf :: proc(msg1, msg2: string) -> [^]f32 {
	// TODO: Set error msg
	stbi_error_msg1, stbi_error_msg2 = msg1, msg2;
	return nil;
}

stbi__errpuc :: proc(msg1, msg2: string) -> [^]u8 {
	// TODO: Set error msg
	stbi_error_msg1, stbi_error_msg2 = msg1, msg2;
	return nil;
}

STBI_FREE :: proc(data: rawptr) {
	// TODO
}

STBI_REALLOC_SIZED :: proc(data: rawptr, old_size, new_size: int) -> rawptr {
	/*// TODO
	return nil;*/
	result, err := mem.resize(data, old_size, new_size);
	return result;
} 

STBI_NOTUSED :: proc(v: $T) {

}

STBI__BYTECAST :: proc(v: int) -> u8 {
	return cast(u8)(v&255);
}

///////////////////////////////////////////////
//
//  stbi__context struct and start_xxx functions

// stbi__context structure is our basic context used by all images, so it
// contains all the IO context, plus some basic image information
stbi__context :: struct {
   img_x, img_y: u32,
   img_n, img_out_n: int,

   /*io: stbi_io_callbacks,
   io_user_data: rawptr,*/

   read_from_callbacks: int,
   buflen: int,
   buffer_start: [128]u8,

   img_buffer, img_buffer_end: ^u8,
   img_buffer_original, img_buffer_original_end: ^u8,
}

stbi__png :: struct {
   s: ^stbi__context,
   idata, expanded, out: ^u8,
   depth: int,
}

stbi__result_info :: struct {
   bits_per_channel: int,
   num_channels: int,
   channel_order: int,
}

//////////////////////////////////////////////////////////////////////////////
//
// Common code used by all image loaders
//

STBI_Scan :: enum
{
   load=0,
   type,
   header
};

STBI__F :: enum {
   none=0,
   sub=1,
   up=2,
   avg=3,
   paeth=4,
   // synthetic filters used for first scanline to avoid needing a dummy row of 0s
   avg_first,
   paeth_first
};

first_row_filter:=[5]u8 {
   cast(u8)STBI__F.none,
   cast(u8)STBI__F.sub,
   cast(u8)STBI__F.none,
   cast(u8)STBI__F.avg_first,
   cast(u8)STBI__F.paeth_first
}

stbi__paeth :: proc(a, b, c: int) -> int
{
   p  := a + b - c;
   pa := math.abs(p-a);
   pb := math.abs(p-b);
   pc := math.abs(p-c);
   if (pa <= pb && pa <= pc) do return a;
   if (pb <= pc) do return b;
   return c;
}


// create the png data from post-deflated data
stbi__create_png_image_raw :: proc(a: ^stbi__png, arg_raw: []u8, out_n: int, x, y: u32, depth, color: int) -> bool
{
   raw := arg_raw;
   bytes := (depth == 16 ? 2 : 1);
   s := a.s;
   //stbi__uint32 i,j,
   stride :u32= x*u32(out_n*bytes);
   img_len, img_width_bytes: u32;
   //int k;
   img_n := s.img_n; // copy it into a local for later

   output_bytes := out_n*bytes;
   filter_bytes := img_n*bytes;
   width := x;

   STBI_ASSERT(out_n == s.img_n || out_n == s.img_n+1);
   a.out = cast(^u8) stbi__malloc_mad3(cast(int)x, cast(int)y, output_bytes, 0); // extra bytes to write off the end into
   if (a.out == nil) do return stbi__err("outofmem", "Out of memory");

   if (!stbi__mad3sizes_valid(img_n, cast(int)x, depth, 7)) do return stbi__err("too large", "Corrupt PNG");
   img_width_bytes = (((cast(u32)img_n * x * cast(u32)depth) + 7) >> 3);
   img_len = (img_width_bytes + 1) * y;

   // we used to check for exact match between raw_len and img_len on non-interlaced PNGs,
   // but issue #276 reported a PNG in the wild that had extra data at the end (all zeros),
   // so just check for raw_len < img_len always.
   if (len(raw) < cast(int)img_len) do return stbi__err("not enough pixels","Corrupt PNG");

   for j in 0..<y {
      cur := cast([^]u8)intrinsics.ptr_offset(a.out, stride*j);
      prior: [^]u8;
      filter := cast(int)raw[0];
      //raw = intrinsics.ptr_offset(raw, 1);
      raw = raw[1:];

      if (filter > 4) do return stbi__err("invalid filter","Corrupt PNG");

      if (depth < 8) {
         STBI_ASSERT(img_width_bytes <= x);
         cur = intrinsics.ptr_offset(cur, x*cast(u32)out_n - img_width_bytes); // store output to the rightmost img_len bytes, so we can decode in place
         filter_bytes = 1;
         width = img_width_bytes;
      }
      prior = intrinsics.ptr_offset(cur, -cast(int)stride); // bugfix: need to compute this after 'cur +=' computation above

      // if first row, use special filter that doesn't sample previous row
      if (j == 0) do filter = cast(int)first_row_filter[filter];

      // handle first byte explicitly
      for k in 0..<filter_bytes {
         switch (filter) {
            case cast(int)STBI__F.none       : cur[k] = raw[k];
            case cast(int)STBI__F.sub        : cur[k] = raw[k];
            case cast(int)STBI__F.up         : cur[k] = STBI__BYTECAST(cast(int)(raw[k] + prior[k]));
            case cast(int)STBI__F.avg        : cur[k] = STBI__BYTECAST(cast(int)raw[k] + cast(int)(prior[k]>>1));
            case cast(int)STBI__F.paeth      : cur[k] = STBI__BYTECAST(cast(int)raw[k] + stbi__paeth(0,cast(int)prior[k],0));
            case cast(int)STBI__F.avg_first  : cur[k] = raw[k];
            case cast(int)STBI__F.paeth_first: cur[k] = raw[k];
         }
      }

      if (depth == 8) {
         if (img_n != out_n) do cur[img_n] = 255; // first pixel
         raw = raw[img_n:];
         cur = intrinsics.ptr_offset(cur, out_n);
         prior = intrinsics.ptr_offset(prior, out_n);
      } else if (depth == 16) {
         if (img_n != out_n) {
            cur[filter_bytes]   = 255; // first pixel top byte
            cur[filter_bytes+1] = 255; // first pixel bottom byte
         }
         raw = raw[filter_bytes:];
         cur = intrinsics.ptr_offset(cur, output_bytes);
         prior = intrinsics.ptr_offset(prior, output_bytes);
      } else {
         raw = raw[1:];
         cur = intrinsics.ptr_offset(cur, 1);
         prior = intrinsics.ptr_offset(prior, 1);
      }

      // this is a little gross, so that we don't switch per-pixel or per-component
      if (depth < 8 || img_n == out_n) {
         nk: int = (cast(int)width - 1)*filter_bytes;
        
         switch (filter) {
            // "none" filter turns into a memcpy here; make that explicit.
            case cast(int)STBI__F.none: mem.copy(cur, raw_data(raw), cast(int)nk);
            case cast(int)STBI__F.sub:
               for k in 0..<nk { cur[k] = STBI__BYTECAST(int(raw[k]) + cast(int)cur[k-filter_bytes]); }
            case cast(int)STBI__F.up:
               for k in 0..<nk { cur[k] = STBI__BYTECAST(int(raw[k]) + cast(int)prior[k]); }
            case cast(int)STBI__F.avg:
               for k in 0..<nk { cur[k] = STBI__BYTECAST(int(raw[k]) + ((cast(int)prior[k] + cast(int)cur[k-filter_bytes])>>1)); }
            case cast(int)STBI__F.paeth:
               for k in 0..<nk { cur[k] = STBI__BYTECAST(int(raw[k]) + stbi__paeth(cast(int)cur[k-filter_bytes],cast(int)prior[k],cast(int)prior[k-filter_bytes])); }
            case cast(int)STBI__F.avg_first:
               for k in 0..<nk { cur[k] = STBI__BYTECAST(int(raw[k]) + (cast(int)cur[k-filter_bytes] >> 1)); }
            case cast(int)STBI__F.paeth_first:
               for k in 0..<nk { cur[k] = STBI__BYTECAST(int(raw[k]) + stbi__paeth(cast(int)cur[k-filter_bytes],0,0)); }
         }
         raw = raw[nk:];
      } else {
         STBI_ASSERT(img_n+1 == out_n);
         
         switch (filter) {
            case cast(int)STBI__F.none       :  
               for i := x-1; i >= 1; i-=1 {
                  for k in 0..<filter_bytes { cur[k] = raw[k]; }
                  cur[filter_bytes] = 255;
                  raw = raw[filter_bytes:];
                  cur = intrinsics.ptr_offset(cur, output_bytes);
                  prior = intrinsics.ptr_offset(prior, output_bytes);
               }
            case cast(int)STBI__F.sub        :  
               for i := x-1; i >= 1; i-=1 {
                  for k in 0..<filter_bytes { cur[k] = STBI__BYTECAST(cast(int)raw[k] + cast(int)cur[k- output_bytes]); }
                  cur[filter_bytes] = 255;
                  raw = raw[filter_bytes:];
                  cur = intrinsics.ptr_offset(cur, output_bytes);
                  prior = intrinsics.ptr_offset(prior, output_bytes);
               }
            case cast(int)STBI__F.up         :  
               for i := x-1; i >= 1; i-=1 {
                  for k in 0..<filter_bytes { cur[k] = STBI__BYTECAST(cast(int)raw[k] + cast(int)prior[k]); }
                  cur[filter_bytes] = 255;
                  raw = raw[filter_bytes:];
                  cur = intrinsics.ptr_offset(cur, output_bytes);
                  prior = intrinsics.ptr_offset(prior, output_bytes);
               }
            case cast(int)STBI__F.avg        :  
               for i := x-1; i >= 1; i-=1 {
                  for k in 0..<filter_bytes { cur[k] = STBI__BYTECAST(cast(int)raw[k] + ((cast(int)prior[k] + cast(int)cur[k- output_bytes])>>1)); }
                  cur[filter_bytes] = 255;
                  raw = raw[filter_bytes:];
                  cur = intrinsics.ptr_offset(cur, output_bytes);
                  prior = intrinsics.ptr_offset(prior, output_bytes);
               }
            case cast(int)STBI__F.paeth      :  
               for i := x-1; i >= 1; i-=1 {
                  for k in 0..<filter_bytes { cur[k] = STBI__BYTECAST(cast(int)raw[k] + stbi__paeth(cast(int)cur[k- output_bytes],cast(int)prior[k],cast(int)prior[k- output_bytes])); }
                  cur[filter_bytes] = 255;
                  raw = raw[filter_bytes:];
                  cur = intrinsics.ptr_offset(cur, output_bytes);
                  prior = intrinsics.ptr_offset(prior, output_bytes);
               }
            case cast(int)STBI__F.avg_first  :  
               for i := x-1; i >= 1; i-=1 {
                  for k in 0..<filter_bytes { cur[k] = STBI__BYTECAST(cast(int)raw[k] + (cast(int)cur[k- output_bytes] >> 1)); }
                  cur[filter_bytes] = 255;
                  raw = raw[filter_bytes:];
                  cur = intrinsics.ptr_offset(cur, output_bytes);
                  prior = intrinsics.ptr_offset(prior, output_bytes);
               }
            case cast(int)STBI__F.paeth_first:  
               for i := x-1; i >= 1; i-=1 {
                  for k in 0..<filter_bytes { cur[k] = STBI__BYTECAST(cast(int)raw[k] + stbi__paeth(cast(int)cur[k- output_bytes],0,0)); }
                  cur[filter_bytes] = 255;
                  raw = raw[filter_bytes:];
                  cur = intrinsics.ptr_offset(cur, output_bytes);
                  prior = intrinsics.ptr_offset(prior, output_bytes);
               }
         }

         // the loop above sets the high byte of the pixels' alpha, but for
         // 16 bit png files we also need the low byte set. we'll do that here.
         if (depth == 16) {
            cur = intrinsics.ptr_offset(a.out, stride*j); // start at the beginning of the row again
            for i in 0..<x {
               cur[filter_bytes+1] = 255;
               cur = intrinsics.ptr_offset(cur, output_bytes);
            }
         }
      }
   }

   // we make a separate pass to expand bits to pixels; for performance,
   // this could run two scanlines behind the above code, so it won't
   // intefere with filtering but will still be in the cache.
   if (depth < 8) {
      for j in 0..<y {
         cur := cast([^]u8)intrinsics.ptr_offset(a.out, stride*j);
         inp := cast(^u8)intrinsics.ptr_offset(a.out, stride*j + x*cast(u32)out_n - img_width_bytes);
         // unpack 1/2/4-bit into a 8-bit buffer. allows us to keep the common 8-bit path optimal at minimal cost for 1/2/4-bit
         // png guarante byte alignment, if width is not multiple of 8/4/2 we'll decode dummy trailing data that will be skipped in the later loop
         scale := u8((color == 0) ? stbi__depth_scale_table[depth] : 1); // scale grayscale values to 0..255 range

         // note that the final byte might overshoot and write more data than desired.
         // we can allocate enough data that this never writes out of memory, but it
         // could also overwrite the next scanline. can it overwrite non-empty data
         // on the next scanline? yes, consider 1-pixel-wide scanlines with 1-bit-per-pixel.
         // so we need to explicitly clamp the final ones
         k: u32;
         if (depth == 4) {

            for k=x*cast(u32)img_n; k >= 2; k-=2 {
               cur[0] = scale * ((inp^ >> 4)       );
               cur[1] = scale * ((inp^     ) & 0x0f);
               cur = intrinsics.ptr_offset(cur, 2);
               inp = intrinsics.ptr_offset(inp, 1);
            }
            if (k > 0) {
               cur[0] = scale * ((inp^ >> 4)       );
               cur = intrinsics.ptr_offset(cur, 1);
            }
         } else if (depth == 2) {
            for k=x*cast(u32)img_n; k >= 4; k-=4 {
               cur[0] = scale * ((inp^ >> 6)       );
               cur[1] = scale * ((inp^ >> 4) & 0x03);
               cur[2] = scale * ((inp^ >> 2) & 0x03);
               cur[3] = scale * ((inp^     ) & 0x03);
               cur = intrinsics.ptr_offset(cur, 4);
               inp = intrinsics.ptr_offset(inp, 1);
            }
            if (k > 0) {
               cur[0] = scale * ((inp^ >> 6)       );
               cur = intrinsics.ptr_offset(cur, 1);
            }
            if (k > 1) {
               cur[0] = scale * ((inp^ >> 4) & 0x03);
               cur = intrinsics.ptr_offset(cur, 1);
            }
            if (k > 2) {
               cur[0] = scale * ((inp^ >> 2) & 0x03);
               cur = intrinsics.ptr_offset(cur, 1);
            }
         } else if (depth == 1) {
            for k=x*cast(u32)img_n; k >= 8; k-=8 {
               cur[0] = scale * ((inp^ >> 7)       );
               cur[1] = scale * ((inp^ >> 6) & 0x01);
               cur[2] = scale * ((inp^ >> 5) & 0x01);
               cur[3] = scale * ((inp^ >> 4) & 0x01);
               cur[4] = scale * ((inp^ >> 3) & 0x01);
               cur[5] = scale * ((inp^ >> 2) & 0x01);
               cur[6] = scale * ((inp^ >> 1) & 0x01);
               cur[7] = scale * ((inp^     ) & 0x01);
               cur = intrinsics.ptr_offset(cur, 8);
               inp = intrinsics.ptr_offset(inp, 1);
            }
            if (k > 0) {
               cur[0] = scale * ((inp^ >> 7)       );
               cur = intrinsics.ptr_offset(cur, 1);
            }
            if (k > 1) {
               cur[0] = scale * ((inp^ >> 6) & 0x01);
               cur = intrinsics.ptr_offset(cur, 1);
            }
            if (k > 2) {
               cur[0] = scale * ((inp^ >> 5) & 0x01);
               cur = intrinsics.ptr_offset(cur, 1);
            }
            if (k > 3) {
               cur[0] = scale * ((inp^ >> 4) & 0x01);
               cur = intrinsics.ptr_offset(cur, 1);
            }
            if (k > 4) {
               cur[0] = scale * ((inp^ >> 3) & 0x01);
               cur = intrinsics.ptr_offset(cur, 1);
            }
            if (k > 5) {
               cur[0] = scale * ((inp^ >> 2) & 0x01);
               cur = intrinsics.ptr_offset(cur, 1);
            }
            if (k > 6) {
               cur[0] = scale * ((inp^ >> 1) & 0x01);
               cur = intrinsics.ptr_offset(cur, 1);
            }
         }
         if (img_n != out_n) {
            // insert alpha = 255
            cur = intrinsics.ptr_offset(a.out, stride*j);
            if (img_n == 1) {
               for q:=x-1; q >= 0; q-=1 {
                  cur[q*2+1] = 255;
                  cur[q*2+0] = cur[q];
               }
            } else {
               STBI_ASSERT(img_n == 3);
               for q:=x-1; q >= 0; q-=1 {
                  cur[q*4+3] = 255;
                  cur[q*4+2] = cur[q*3+2];
                  cur[q*4+1] = cur[q*3+1];
                  cur[q*4+0] = cur[q*3+0];
               }
            }
         }
      }
   } else if (depth == 16) {
      // force the image data from big-endian to platform-native.
      // this is done in a separate pass due to the decoding relying
      // on the data being untouched, but could probably be done
      // per-line during decode if care is taken.
      cur := cast([^]u8)a.out;
      cur16 := cast([^]u16)cur;

      for i in 0..<x*y*cast(u32)out_n {
         cur16[0] = (cast(u16)cur[0] << 8) | cast(u16)cur[1];

         cur16 = intrinsics.ptr_offset(cur16, 1);
         cur   = intrinsics.ptr_offset(cur  , 2);
      }
   }

   return true;
}

stbi__create_png_image :: proc(a: ^stbi__png, image_data: []u8, out_n, depth, color: int, interlaced: bool) -> bool
{
   image_data := image_data;
   bytes := (depth == 16 ? 2 : 1);
   out_bytes := out_n * bytes;
   /*stbi_uc *final;
   int p;*/
   if (!interlaced) do return stbi__create_png_image_raw(a, image_data, out_n, a.s.img_x, a.s.img_y, depth, color);

   // de-interlacing
   final := cast(^u8) stbi__malloc_mad3(cast(int)a.s.img_x, cast(int)a.s.img_y, out_bytes, 0);
   for p in 0..<7 {
      xorig: [7]int = { 0,4,0,2,0,1,0 };
      yorig: [7]int = { 0,0,4,0,2,0,1 };
      xspc:  [7]int = { 8,8,4,4,2,2,1 };
      yspc:  [7]int = { 8,8,8,4,4,2,2 };
      //int i,j,x,y;
      // pass1_x[4] = 0, pass1_x[5] = 1, pass1_x[12] = 1
      x := (cast(int)a.s.img_x - xorig[p] + xspc[p]-1) / xspc[p];
      y := (cast(int)a.s.img_y - yorig[p] + yspc[p]-1) / yspc[p];
      if (x!=0 && y!=0) {
         img_len := cast(u32)(((((a.s.img_n * x * depth) + 7) >> 3) + 1) * y);
         if (!stbi__create_png_image_raw(a, image_data, out_n, cast(u32)x, cast(u32)y, depth, color)) {
            STBI_FREE(final);
            return false;
         }
         for j in 0..<y {
            for i in 0..<x {
               out_y := j*yspc[p]+yorig[p];
               out_x := i*xspc[p]+xorig[p];
               mem.copy(intrinsics.ptr_offset(final, out_y*cast(int)a.s.img_x*out_bytes + out_x*out_bytes),
                        intrinsics.ptr_offset(a.out, (j*x+i)*out_bytes), 
                        out_bytes);
            }
         }
         STBI_FREE(a.out);
         image_data = image_data[img_len:];
      }
   }
   a.out = final;

   return true;
}

stbi__compute_transparency :: proc(z: ^stbi__png, tc: [3]u8, out_n: int) -> bool
{
   s := z.s;
   pixel_count := s.img_x * s.img_y;
   p := cast([^]u8)z.out;

   // compute color-based transparency, assuming we've
   // already got 255 as the alpha value in the output
   STBI_ASSERT(out_n == 2 || out_n == 4);

   if (out_n == 2) {
      for i in 0..<pixel_count {
         p[1] = (p[0] == tc[0] ? 0 : 255);
         p = intrinsics.ptr_offset(p, 2);
      }
   } else {
      for i in 0..<pixel_count {
         if (p[0] == tc[0] && p[1] == tc[1] && p[2] == tc[2]) {
            p[3] = 0;
         }
         p = intrinsics.ptr_offset(p, 4);
      }
   }
   return true;
}

stbi__compute_transparency16 :: proc(z: ^stbi__png, tc: [3]u16, out_n: int) -> bool
{
   s := z.s;
   pixel_count := s.img_x * s.img_y;
   p := cast([^]u16) z.out;

   // compute color-based transparency, assuming we've
   // already got 65535 as the alpha value in the output
   STBI_ASSERT(out_n == 2 || out_n == 4);

   if (out_n == 2) {
      for i in 0..<pixel_count {
         p[1] = (p[0] == tc[0] ? 0 : 65535);
         p = intrinsics.ptr_offset(p, 2);         
      }
   } else {
      for i in 0..<pixel_count {
         if (p[0] == tc[0] && p[1] == tc[1] && p[2] == tc[2]) {
            p[3] = 0;
         }
         p = intrinsics.ptr_offset(p, 4);
      }
   }
   return true;
}

stbi__expand_png_palette :: proc(a: ^stbi__png, palette: []u8, pal_img_n: int) -> bool
{
   pixel_count := a.s.img_x * a.s.img_y;
   orig := cast([^]u8)a.out;

   p := cast([^]u8) stbi__malloc_mad2(cast(int)pixel_count, pal_img_n, 0);
   if (p == nil) do return stbi__err("outofmem", "Out of memory");

   // between here and free(out) below, exitting would leak
   temp_out := p;

   if (pal_img_n == 3) {
      for i in 0..<pixel_count {
         n := cast(int)orig[i]*4;
         p[0] = palette[n  ];
         p[1] = palette[n+1];
         p[2] = palette[n+2];
         p = intrinsics.ptr_offset(p, 3);
      }
   } else {
      for i in 0..<pixel_count {
         n := cast(int)orig[i]*4;
         p[0] = palette[n  ];
         p[1] = palette[n+1];
         p[2] = palette[n+2];
         p[3] = palette[n+3];
         p = intrinsics.ptr_offset(p, 4);
      }
   }
   STBI_FREE(a.out);
   a.out = temp_out;

   return true;
}

stbi__skip :: proc(s: ^stbi__context, n: int)
{
   if (n < 0) {
      s.img_buffer = s.img_buffer_end;
      return;
   }
   // TODO: IO
   /*if (s.io.read) {
      int blen = (int) (s.img_buffer_end - s.img_buffer);
      if (blen < n) {
         s.img_buffer = s.img_buffer_end;
         (s.io.skip)(s.io_user_data, n - blen);
         return;
      }
   }*/
   s.img_buffer = intrinsics.ptr_offset(s.img_buffer, n);
}


stbi__getn :: proc(s: ^stbi__context, buffer: [^]u8, n: int) -> bool
{
	// TODO: IO
   /*if (s.io.read) {
      int blen = (int) (s.img_buffer_end - s.img_buffer);
      if (blen < n) {
         int res, count;

         memcpy(buffer, s.img_buffer, blen);

         count = (s.io.read)(s.io_user_data, (char*) buffer + blen, n - blen);
         res = (count == (n-blen));
         s.img_buffer = s.img_buffer_end;
         return res;
      }
   }*/

   new_end := intrinsics.ptr_offset(s.img_buffer, n);
   if (new_end <= s.img_buffer_end) {
      mem.copy(buffer, s.img_buffer, n);
      s.img_buffer = new_end;
      return true;
   } else {
      return false;
   }
}


stbi__get8 :: proc(s: ^stbi__context) -> u8
{
	if(s.img_buffer < s.img_buffer_end) {
		result := s.img_buffer^;
		s.img_buffer = s.img_buffer
		s.img_buffer = intrinsics.ptr_offset(s.img_buffer, 1);
		return result;
	}
	return 0;

	// TODO: IO
   /*if (s.img_buffer_cursor < len(s.img_buffer)) {
   		s.img_buffer_cursor += 1;
      return s.img_buffer[s.img_buffer_cursor-1];
   }
   if (s.read_from_callbacks) {
      stbi__refill_buffer(s);
      s.img_buffer_cursor += 1;
      return s.img_buffer[s.img_buffer_cursor-1];
   }
   return 0;*/
}

/*stbi__get16be :: proc(s: ^stbi__context) -> int
{
   z : int = int(stbi__get8(s));
   return (z << 8) + int(stbi__get8(s));
}*/

stbi__get16be :: proc(s: ^stbi__context) -> u16
{
   z := u16(stbi__get8(s));
   return (z << 8) + u16(stbi__get8(s));
}


stbi__get32be :: proc(s: ^stbi__context) -> u32
{
   z := stbi__get16be(s);
   return (cast(u32)z << 16) + cast(u32)stbi__get16be(s);
}


// public domain "baseline" PNG decoder   v0.10  Sean Barrett 2006-11-18
//    simple implementation
//      - only 8-bit samples
//      - no CRC checking
//      - allocates lots of intermediate memory
//        - avoids problem of streaming data between subsystems
//        - avoids explicit window management
//    performance
//      - uses stb_zlib, a PD zlib implementation with fast huffman decoding

stbi__pngchunk :: struct {
   length, type: u32,
}

stbi__get_chunk_header :: proc(s: ^stbi__context) -> stbi__pngchunk
{
   c: stbi__pngchunk;
   c.length = stbi__get32be(s);
   c.type   = stbi__get32be(s);
   return c;
}


stbi__check_png_header :: proc(s: ^stbi__context) -> bool
{
   png_sig_c :: [8]u8 { 137,80,78,71,13,10,26,10 };
   png_sig := png_sig_c;
   for i in 0..<8 {
   	  f := stbi__get8(s);
   	  s := png_sig[i];
      if (f != s) do return stbi__err("bad png sig","Not a PNG");
   }
   return true;
}

stbi__depth_scale_table := [9]u8 { 0, 0xff, 0x55, 0, 0x11, 0,0,0, 0x01 }

STBI__PNG_TYPE_CgBI :: ('C' << 24 | 'g' << 16 | 'B' << 8 | 'I');
STBI__PNG_TYPE_IHDR :: ('I' << 24 | 'H' << 16 | 'D' << 8 | 'R');
STBI__PNG_TYPE_PLTE :: ('P' << 24 | 'L' << 16 | 'T' << 8 | 'E');
STBI__PNG_TYPE_tRNS :: ('t' << 24 | 'R' << 16 | 'N' << 8 | 'S');
STBI__PNG_TYPE_IDAT :: ('I' << 24 | 'D' << 16 | 'A' << 8 | 'T');
STBI__PNG_TYPE_IEND :: ('I' << 24 | 'E' << 16 | 'N' << 8 | 'D');


stbi__parse_png_file :: proc(z: ^stbi__png, scan: STBI_Scan, req_comp: int) -> bool
{
   palette: [1024]u8;
   pal_img_n: u8 = 0;
   has_trans: bool = false;
   tc: [3]u8 = {0, 0, 0};
   tc16: [3]u16;
   ioff: u32 =0;
   idata_limit: u32 = 0;
   pal_len: u32 = 0;
   first: bool = true;
   interlace := false;
   color: int = 0;
   is_iphone: bool = false;
   s := z.s;

   z.expanded = nil;
   z.idata = nil;
   z.out = nil;

   if (!stbi__check_png_header(s)) do return false;

   if (scan == .type) do return true;

	
   for {
      c := stbi__get_chunk_header(s);
      switch (c.type) {
         case STBI__PNG_TYPE_CgBI:
            is_iphone = true;
            stbi__skip(s, cast(int)c.length);
         case STBI__PNG_TYPE_IHDR: {
            comp,filter: int;
            if (!first) do return stbi__err("multiple IHDR","Corrupt PNG");
            first = false;
            if (c.length != 13) do return stbi__err("bad IHDR len","Corrupt PNG");
            s.img_x = stbi__get32be(s); if (s.img_x > (1 << 24)) do return stbi__err("too large","Very large image (corrupt?)");
            s.img_y = stbi__get32be(s); if (s.img_y > (1 << 24)) do return stbi__err("too large","Very large image (corrupt?)");
            z.depth = cast(int)stbi__get8(s);  if (z.depth != 1 && z.depth != 2 && z.depth != 4 && z.depth != 8 && z.depth != 16)  do return stbi__err("1/2/4/8/16-bit only","PNG not supported: 1/2/4/8/16-bit only");
            color = cast(int)stbi__get8(s);  if (color > 6)         do return stbi__err("bad ctype","Corrupt PNG");
            if (color == 3 && z.depth == 16)                  do return stbi__err("bad ctype","Corrupt PNG");
            if (color == 3) {
            	pal_img_n = 3; 	
            } else if ((color & 1) != 0) do return stbi__err("bad ctype","Corrupt PNG");
            comp  = cast(int)stbi__get8(s);  if (comp != 0) do return stbi__err("bad comp method","Corrupt PNG");
            filter= cast(int)stbi__get8(s);  if (filter != 0) do return stbi__err("bad filter method","Corrupt PNG");
            interlace_int := stbi__get8(s); if (interlace_int>1) do return stbi__err("bad interlace method","Corrupt PNG");
            interlace = interlace_int != 0;
            if (s.img_x == 0 || s.img_y == 0) do return stbi__err("0-pixel image","Corrupt PNG");
            if (pal_img_n == 0) {
               s.img_n = ((color & 2) != 0 ? 3 : 1) + ((color & 4) != 0 ? 1 : 0);
               if ((1 << 30) / int(s.img_x) / int(s.img_n) < int(s.img_y)) do return stbi__err("too large", "Image too large to decode");
               if (scan == .header) do return true;
            } else {
               // if paletted, then pal_n is our final components, and
               // img_n is # components to decompress/filter.
               s.img_n = 1;
               if ((1 << 30) / s.img_x / 4 < s.img_y) do return stbi__err("too large","Corrupt PNG");
               // if SCAN_header, have to scan to see if we have a tRNS
            }
            break;
         }

         case STBI__PNG_TYPE_PLTE:  {
            if (first) do return stbi__err("first not IHDR", "Corrupt PNG");
            if (c.length > 256*3) do return stbi__err("invalid PLTE","Corrupt PNG");
            pal_len = c.length / 3;
            if (pal_len * 3 != c.length) do return stbi__err("invalid PLTE","Corrupt PNG");
            for i in 0..<pal_len {
               palette[i*4+0] = stbi__get8(s);
               palette[i*4+1] = stbi__get8(s);
               palette[i*4+2] = stbi__get8(s);
               palette[i*4+3] = 255;
            }
            break;
         }

         case STBI__PNG_TYPE_tRNS: {
            if (first) do return stbi__err("first not IHDR", "Corrupt PNG");
            if (z.idata != nil) do return stbi__err("tRNS after IDAT","Corrupt PNG");
            if (pal_img_n != 0) {
               if (scan == .header) { s.img_n = 4; return true; }
               if (pal_len == 0) do return stbi__err("tRNS before PLTE","Corrupt PNG");
               if (c.length > pal_len) do return stbi__err("bad tRNS len","Corrupt PNG");
               pal_img_n = 4;
               for i in 0..<c.length do palette[i*4+3] = stbi__get8(s);
            } else {
               if ((s.img_n & 1) == 0) do return stbi__err("tRNS with alpha","Corrupt PNG");
               if (c.length != cast(u32) s.img_n*2) do return stbi__err("bad tRNS len","Corrupt PNG");
               has_trans = true;
               if (z.depth == 16) {
                  for k in 0..<s.img_n do tc16[k] = cast(u16)stbi__get16be(s); // copy the values as-is
               } else {
                  for k in 0..<s.img_n do tc[k] = (u8)(stbi__get16be(s) & 255) * stbi__depth_scale_table[z.depth]; // non 8-bit images will be larger
               }
            }
         }

         case STBI__PNG_TYPE_IDAT: {
            if (first) do return stbi__err("first not IHDR", "Corrupt PNG");
            if (pal_img_n != 0 && pal_len == 0) do return stbi__err("no PLTE","Corrupt PNG");
            if (scan == .header) { s.img_n = cast(int)pal_img_n; return true; }
            if ((int)(ioff + c.length) < cast(int)ioff) do return false;
            if (ioff + c.length > idata_limit) {
               idata_limit_old := idata_limit;
               p: ^u8;
               if (idata_limit == 0) do idata_limit = c.length > 4096 ? c.length : 4096;
               for ioff + c.length > idata_limit do idata_limit *= 2;
               STBI_NOTUSED(idata_limit_old);
               p = cast(^u8) STBI_REALLOC_SIZED(z.idata, cast(int)idata_limit_old, cast(int)idata_limit); 
               if (p == nil) do return stbi__err("outofmem", "Out of memory");
               z.idata = p;
            }
            if (!stbi__getn(s, intrinsics.ptr_offset(z.idata, ioff), cast(int)c.length)) do return stbi__err("outofdata","Corrupt PNG");
            ioff += c.length;
         }

         case STBI__PNG_TYPE_IEND: {
            raw_len, bpl: u32;
            if (first) do return stbi__err("first not IHDR", "Corrupt PNG");
            if (scan != .load) do return true;
            if (z.idata == nil) do return stbi__err("no IDAT","Corrupt PNG");
            // initial guess for decoded data size to avoid unnecessary reallocs
            bpl = (s.img_x * cast(u32)z.depth + 7) / 8; // bytes per line, per component
            raw_len = (bpl * s.img_y * cast(u32)s.img_n /* pixels */ + s.img_y /* filter mode per row */);
            z.expanded = cast(^u8) stbi_zlib_decode_malloc_guesssize_headerflag(z.idata, cast(int)ioff, cast(int)raw_len, cast(^int) &raw_len, !is_iphone);
            if (z.expanded == nil) do return false; // zlib should set error
            STBI_FREE(z.idata); z.idata = nil;
            if ((req_comp == s.img_n+1 && req_comp != 3 && pal_img_n == 0) || has_trans) {
               s.img_out_n = s.img_n+1;
            }
            else {
               s.img_out_n = s.img_n;
            }
            if (!stbi__create_png_image(z, mem.byte_slice(z.expanded, raw_len), s.img_out_n, z.depth, color, interlace)) do return false;
            if (has_trans) {
               if (z.depth == 16) {
                  if (!stbi__compute_transparency16(z, tc16, s.img_out_n)) do return false;
               } else {
                  if (!stbi__compute_transparency(z, tc, s.img_out_n)) do return false;
               }
            }
            //if (is_iphone && stbi__de_iphone_flag && s.img_out_n > 2) do stbi__de_iphone(z); // TODO: IPHONE?
            if (pal_img_n != 0) {
               // pal_img_n == 3 or 4
               s.img_n = cast(int)pal_img_n; // record the actual colors we had
               s.img_out_n = cast(int)pal_img_n;
               if (req_comp >= 3) do s.img_out_n = req_comp;
               if (!stbi__expand_png_palette(z, palette[:pal_len], s.img_out_n)) do return false;
            } else if (has_trans) {
               // non-paletted image with tRNS -> source image has (constant) alpha
               s.img_n += 1;
            }
            STBI_FREE(z.expanded); z.expanded = nil;
            return true;
         }

         case:
            // if critical, fail
            if (first) do return stbi__err("first not IHDR", "Corrupt PNG");
            if ((c.type & (1 << 29)) == 0) {
               //#ifndef STBI_NO_FAILURE_STRINGS
               // not threadsafe
               /*invalid_chunk := "XXXX PNG chunk not known";
               invalid_chunk[0] = STBI__BYTECAST(c.type >> 24);
               invalid_chunk[1] = STBI__BYTECAST(c.type >> 16);
               invalid_chunk[2] = STBI__BYTECAST(c.type >>  8);
               invalid_chunk[3] = STBI__BYTECAST(c.type >>  0);*/
               //#endif
               return stbi__err("invalid_chunk", "PNG not supported: unknown PNG chunk type");
            }
            stbi__skip(s, cast(int)c.length);
      }
      // end of PNG chunk, read and skip CRC
      stbi__get32be(s);
   }
   return true;
}

stbi__do_png :: proc(p: ^stbi__png, x, y, n: ^int, req_comp: int, ri: ^stbi__result_info) -> rawptr
{
   result: rawptr = nil;
   if (req_comp < 0 || req_comp > 4) do return stbi__errpuc("bad req_comp", "Internal error");
   if (stbi__parse_png_file(p, .load, req_comp)) {
      if (p.depth < 8) do ri.bits_per_channel = 8;
      else              do ri.bits_per_channel = p.depth;
      result = p.out;
      p.out = nil;
      if (req_comp != 0 && req_comp != p.s.img_out_n) {
        if (ri.bits_per_channel == 8) {
            result = stbi__convert_format(cast(^u8) result, p.s.img_out_n, req_comp, cast(uint)p.s.img_x, cast(uint)p.s.img_y);
        }
        else {
        	assert(false, "Not implemented");
            //result = stbi__convert_format16(cast(^u16) result, p.s.img_out_n, req_comp, p.s.img_x, p.s.img_y);
        }
         p.s.img_out_n = req_comp;
         if (result == nil) do return result;
      }
      x^ = cast(int)p.s.img_x;
      y^ = cast(int)p.s.img_y;
      if (n != nil) do n^ = cast(int)p.s.img_n;
   }
   STBI_FREE(p.out);      p.out      = nil;
   STBI_FREE(p.expanded); p.expanded = nil;
   STBI_FREE(p.idata);    p.idata    = nil;

   return result;
}

stbi_load_png_from_memory :: proc(memory: []u8, x, y, comp: ^int, req_comp: int) -> rawptr {
   s: stbi__context;
   s.img_buffer = &memory[0];
   s.img_buffer_end = intrinsics.ptr_offset(s.img_buffer, len(memory));

   s.img_buffer_original = s.img_buffer;
   s.img_buffer_original_end = s.img_buffer_end;

   ri: stbi__result_info;

   return stbi__png_load(&s, x, y, comp, req_comp, &ri);
} 

stbi__png_load :: proc(s: ^stbi__context, x, y, comp: ^int, req_comp: int, ri: ^stbi__result_info) -> rawptr
{
   p: stbi__png;
   p.s = s;
   return stbi__do_png(&p, x,y,comp,req_comp, ri);
}

// fast-way is faster to check than jpeg huffman, but slow way is slower
STBI__ZFAST_BITS :: 9; // accelerate all cases in default tables
STBI__ZFAST_MASK :: ((1 << STBI__ZFAST_BITS) - 1);

// zlib-style huffman encoding
// (jpegs packs from left, zlib from right, so can't share code)
stbi__zhuffman :: struct
{
   fast: [1 << STBI__ZFAST_BITS]u16,
   firstcode: [16]u16,
   maxcode: [17]int,
   firstsymbol: [16]u16,
   size: [288]u8,
   value: [288]u16,
}

stbi__bitreverse16 :: #force_inline proc(n: int) -> int
{
	n := n;
  	n = ((n & 0xAAAA) >>  1) | ((n & 0x5555) << 1);
  	n = ((n & 0xCCCC) >>  2) | ((n & 0x3333) << 2);
  	n = ((n & 0xF0F0) >>  4) | ((n & 0x0F0F) << 4);
  	n = ((n & 0xFF00) >>  8) | ((n & 0x00FF) << 8);
  	return n;
}

stbi__bit_reverse :: #force_inline proc(v, bits: int) -> int
{
   STBI_ASSERT(bits <= 16);
   // to bit reverse n bits, reverse 16 and shift
   // e.g. 11 bits, bit reverse and shift away 5
   return stbi__bitreverse16(v) >> u32(16-bits);
}

stbi__zbuild_huffman :: proc(z: ^stbi__zhuffman, sizelist: []u8) -> bool
{
	num := len(sizelist);
   k: int = 0;
   code: int;
   next_code: [16]int;
   sizes: [17]int;

   // DEFLATE spec for generating codes
   mem.set(raw_data(sizes[:]), 0, size_of(sizes));
   mem.set(raw_data(z.fast[:]), 0, size_of(z.fast));
   for i in 0..<num {
      sizes[sizelist[i]] += 1;
   }
   sizes[0] = 0;
   for i in 1..<16 {
      if (sizes[i] > (1 << u32(i))) do return stbi__err("bad sizes", "Corrupt PNG");
   }
   code = 0;
   for i in 1..<16 {
      next_code[i] = code;
      z.firstcode[i] = cast(u16) code;
      z.firstsymbol[i] = cast(u16) k;
      code = (code + sizes[i]);
      if (sizes[i] != 0) {
         if (code-1 >= (1 << u32(i))) do return stbi__err("bad codelengths","Corrupt PNG");
      }
      z.maxcode[i] = code << u32(16-i); // preshift for inner loop
      code <<= 1;
      k += sizes[i];
   }
   z.maxcode[16] = 0x10000; // sentinel
   for i in 0..<num  {
      s := cast(int)sizelist[i];
      if (s != 0) {
         c := next_code[s] - cast(int)z.firstcode[s] + cast(int)z.firstsymbol[s];
         fastv := (u16) ((s << 9) | i);
         z.size [c] = cast(u8) s;
         z.value[c] = cast(u16)i;
         if (s <= STBI__ZFAST_BITS) {
            j := stbi__bit_reverse(next_code[s],int(s));
            for(j < (1 << STBI__ZFAST_BITS)) {
               z.fast[j] = fastv;
               j += (1 << cast(u32)s);
            }
         }
         next_code[s] += 1;
      }
   }
   return true;
}

// zlib-from-memory implementation for PNG reading
//    because PNG allows splitting the zlib stream arbitrarily,
//    and it's annoying structurally to have PNG call ZLIB call PNG,
//    we require PNG read all the IDATs and combine them into a single
//    memory buffer

stbi__zbuf :: struct
{
   zbuffer, zbuffer_end: ^u8,
   num_bits: int,
   code_buffer: u32,

   zout, zout_start, zout_end: ^i8,
   z_expandable: bool,

   z_length, z_distance: stbi__zhuffman,
}

stbi__zget8 :: proc(z: ^stbi__zbuf) -> u8
{
   if (z.zbuffer >= z.zbuffer_end) do return 0;
   //return *z.zbuffer++;
   result := z.zbuffer^;
   z.zbuffer = intrinsics.ptr_offset(z.zbuffer, 1);
   return result;
}


stbi__fill_bits :: proc(z: ^stbi__zbuf)
{
   for {
      STBI_ASSERT(z.code_buffer < (u32(1) << cast(u32)z.num_bits));
      z.code_buffer |= cast(u32)stbi__zget8(z) << cast(u32)z.num_bits;
      z.num_bits += 8;
      if(z.num_bits > 24) do break;
   }
}

stbi__zreceive :: proc(z: ^stbi__zbuf, n: u32) -> u32
{
   if (u32(z.num_bits) < n) do stbi__fill_bits(z);
   k : u32 = z.code_buffer & ((1 << n) - 1);
   z.code_buffer >>= n;
   z.num_bits -= int(n);
   return k;
}

FAST_BITS ::  9  // larger handles more cases; smaller stomps less cache

stbi__huffman :: struct
{
   fast: [1 << FAST_BITS]u8,
   // weirdly, repacking this into AoS is a 10% speed loss, instead of a win
   code: [256]u16,
   values: [256]u8,
   size: [257]u8,
   maxcode: [18]u32,
   delta: [17]int,   // old 'firstsymbol' - old 'firstcode'
}

stbi__build_huffman :: proc(h: ^stbi__huffman, count: []int) -> bool
{
   //int i,j,k=0;
   k: int = 0;
   code: u32;
   // build size list for each symbol (from JPEG spec)
   for i in 0..<16 {
      for j in 0..<count[i] {
         h.size[k] = cast(u8)(i+1);
         k+=1;
      }
   }
   h.size[k] = 0;

   // compute actual symbols (from jpeg spec)
   code = 0;
   k = 0;
   l := 0;
   for j in 1..=16 {
      // compute delta to add to code to compute symbol id
      h.delta[j] = int(k - cast(int)code);
      if (int(h.size[k]) == j) {
         for (int(h.size[k]) == j) {
            h.code[k] = cast(u16) (code);
            k+=1;
            code += 1;
         }
         if (u32(code-1) >= (u32(1) << u32(j))) do return stbi__err("bad code lengths","Corrupt JPEG");
      }
      // compute largest code + 1 for this size, preshifted as needed later
      h.maxcode[j] = code << u32(16-j);
      code <<= 1;
   }
   h.maxcode[17] = 0xffffffff;

   // build non-spec acceleration table; 255 is flag for not-accelerated
   mem.set(raw_data(h.fast[:]), 255, 1 << FAST_BITS);
   for i in 0..<k {
      s := h.size[i];
      if (s <= FAST_BITS) {
         c := cast(int)h.code[i] << (FAST_BITS-s);
         m := int(1) << (FAST_BITS-s);
         for j in 0..<m {
            h.fast[c+j] = cast(u8) i;
         }
      }
   }
   return true;
}

stbi__zhuffman_decode_slowpath :: proc(a: ^stbi__zbuf, z: ^stbi__zhuffman) -> int
{
   // not resolved by fast table, so compute it the slow way
   // use jpeg approach, which requires MSbits at top
   k := stbi__bit_reverse(cast(int)a.code_buffer, 16);
   s: int;
   for s=STBI__ZFAST_BITS+1; ; s+=1 {
      if (k < z.maxcode[s]) do break;
   }
   if (s == 16) do return -1; // invalid code!
   // code size is s, so:
   b := (k >> u32(16-s)) - cast(int)z.firstcode[s] + cast(int)z.firstsymbol[s];
   STBI_ASSERT(cast(int)z.size[b] == s);
   a.code_buffer >>= u32(s);
   a.num_bits -= s;
   return cast(int)z.value[b];
}

stbi__zhuffman_decode :: proc(a: ^stbi__zbuf, z: ^stbi__zhuffman) -> int
{
   if (a.num_bits < 16) do stbi__fill_bits(a);
   b := cast(int)z.fast[a.code_buffer & STBI__ZFAST_MASK];
   if (b != 0) {
      s := b >> 9;
      a.code_buffer >>= cast(u32)s;
      a.num_bits -= s;
      return b & 511;
   }
   
   return stbi__zhuffman_decode_slowpath(a, z);
}

stbi__zexpand :: proc(z: ^stbi__zbuf, zout: ^i8, n: int) -> bool  // need to make room for n bytes
{
   z.zout = zout;
   if (!z.z_expandable) do return stbi__err("output buffer limit","Corrupt PNG");
   cur   := intrinsics.ptr_sub(z.zout, z.zout_start); // is ptr_sub correct?
   limit := intrinsics.ptr_sub(z.zout_end, z.zout_start); // is ptr_sub correct?
   old_limit := limit;
   for (cur + n > limit) {
      limit *= 2;
   }
   q := cast(^i8) STBI_REALLOC_SIZED(z.zout_start, old_limit, limit);
   STBI_NOTUSED(old_limit);
   if (q == nil) do return stbi__err("outofmem", "Out of memory");
   z.zout_start = q;
   z.zout       = intrinsics.ptr_offset(q, cur);
   z.zout_end   = intrinsics.ptr_offset(q, limit);
   return true;
}

stbi__zlength_base := [31]u32 {
   3,4,5,6,7,8,9,10,11,13,
   15,17,19,23,27,31,35,43,51,59,
   67,83,99,115,131,163,195,227,258,0,0 }

stbi__zlength_extra := [31]u32{ 0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0,0,0 }

stbi__zdist_base := [32]u32 { 1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,
257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577,0,0}

stbi__zdist_extra := [32]u32 { 0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13, 0, 0}

stbi__parse_huffman_block :: proc(a: ^stbi__zbuf) -> bool
{
   zout := cast([^]i8)a.zout;
   for {
      z := stbi__zhuffman_decode(a, &a.z_length);
      if (z < 256) {
         if (z < 0) do return stbi__err("bad huffman code","Corrupt PNG"); // error in huffman codes
         if (zout >= a.zout_end) {
            if (!stbi__zexpand(a, zout, 1)) do return false;
            zout = a.zout;
         }
         zout[0] = i8(z);
         zout = intrinsics.ptr_offset(zout, 1);
      } else {
         len,dist: int;
         if (z == 256) {
            a.zout = zout;
            return true;
         }
         z -= 257;
         len = cast(int)stbi__zlength_base[z];
         if (stbi__zlength_extra[z] != 0) do len += cast(int)stbi__zreceive(a, stbi__zlength_extra[z]);
         z = stbi__zhuffman_decode(a, &a.z_distance);
         if (z < 0) do return stbi__err("bad huffman code","Corrupt PNG");
         dist = cast(int)stbi__zdist_base[z];
         if (stbi__zdist_extra[z] != 0) do dist += cast(int)stbi__zreceive(a, stbi__zdist_extra[z]);
         if (uintptr(zout) - uintptr(a.zout_start) < uintptr(dist)) do return stbi__err("bad dist","Corrupt PNG");
         if (intrinsics.ptr_offset(zout, len) > a.zout_end) {
            if (!stbi__zexpand(a, zout, int(len))) do return false;
            zout = a.zout;
         }
         p := intrinsics.ptr_offset(zout, -dist);
         if (dist == 1) { // run of one byte; common in images.
            v := p[0];
            if (len > 0) { 
            	for ii in 0..<len {
            		zout[ii] = v;
            	}
            	zout = intrinsics.ptr_offset(zout, len);
            }
         } else {
         	if(len > 0) {
	         	for ii in 0..<len {
	        		zout[ii] = p[ii];
	        	}
	        	zout = intrinsics.ptr_offset(zout, len);
         	}
         }
      }
   }
}

stbi__compute_huffman_codes :: proc(a: ^stbi__zbuf) -> bool
{
   length_dezigzag:= [19]u8 { 16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15 };
   z_codelength: stbi__zhuffman;
   lencodes: [286+32+137]u8;//padding for maximum single op
   codelength_sizes: [19]u8;
   //int i,n;

   hlit  := stbi__zreceive(a,5) + 257;
   hdist := stbi__zreceive(a,5) + 1;
   hclen := stbi__zreceive(a,4) + 4;
   ntot  := hlit + hdist;

   mem.zero(raw_data(codelength_sizes[:]), size_of(codelength_sizes));
   for i in 0..<hclen {
      s := stbi__zreceive(a,3);
      codelength_sizes[length_dezigzag[i]] = cast(u8) s;
   }
   if (!stbi__zbuild_huffman(&z_codelength, codelength_sizes[:])) do return false;

   n :u32= 0;
   for (n < ntot) {
      c := stbi__zhuffman_decode(a, &z_codelength);
      if (c < 0 || c >= 19) do return stbi__err("bad codelengths", "Corrupt PNG");
      if (c < 16) {
        lencodes[n] = cast(u8) c; 
        n += 1;
      } 
      else {
         fill: u8 = 0;
         if (c == 16) {
            c = cast(int)stbi__zreceive(a,2)+3;
            if (n == 0) do return stbi__err("bad codelengths", "Corrupt PNG");
            fill = lencodes[n-1];
         } else if (c == 17) {
            c = cast(int)stbi__zreceive(a,3)+3;
         }
         else {
            STBI_ASSERT(c == 18);
            c = cast(int)stbi__zreceive(a,7)+11;
         }
         if (cast(int)(ntot - n) < c) do return stbi__err("bad codelengths", "Corrupt PNG");
         mem.set(&lencodes[n], fill, c);
         n += cast(u32)c;
      }
   }
   if (n != ntot) do return stbi__err("bad codelengths","Corrupt PNG");
   if (!stbi__zbuild_huffman(&a.z_length, lencodes[:hlit])) do return false;
   if (!stbi__zbuild_huffman(&a.z_distance, lencodes[hlit:hlit+hdist])) do return false;
   return true;
}

stbi__parse_uncompressed_block :: proc(a: ^stbi__zbuf) -> bool
{
   header: [4]u8;
   len,nlen,k: int;
   if ((a.num_bits & 7) != 0) {
      stbi__zreceive(a, u32(a.num_bits & 7)); // discard
   }
   // drain the bit-packed data into header
   k = 0;
   for (a.num_bits > 0) {
      header[k] = cast(u8) (a.code_buffer & 255); // suppress MSVC run-time check
      k += 1;
      a.code_buffer >>= 8;
      a.num_bits -= 8;
   }
   STBI_ASSERT(a.num_bits == 0);
   // now fill header the normal way
   for k < 4 {
      header[k] = stbi__zget8(a);
      k += 1;
   }
   len  = cast(int)header[1] * 256 + cast(int)header[0];
   nlen = cast(int)header[3] * 256 + cast(int)header[2];
   if (nlen != (len ~ 0xffff)) do return stbi__err("zlib corrupt","Corrupt PNG");
   if (intrinsics.ptr_offset(a.zbuffer, len) > a.zbuffer_end) do return stbi__err("read past buffer","Corrupt PNG");
   if (intrinsics.ptr_offset(a.zout, len) > a.zout_end) {
      if (!stbi__zexpand(a, a.zout, len)) do return false;
   }
   mem.copy(a.zout, a.zbuffer, len);
   a.zbuffer = intrinsics.ptr_offset(a.zbuffer, len);
   a.zout = intrinsics.ptr_offset(a.zout, len);
   return true;
}

stbi__parse_zlib_header :: proc(a: ^stbi__zbuf) -> bool
{
   cmf   := int(stbi__zget8(a));
   cm    := cmf & 15;
   /* int cinfo = cmf >> 4; */
   flg   := int(stbi__zget8(a));
   if ((cmf*256+flg) % 31 != 0) do return stbi__err("bad zlib header","Corrupt PNG"); // zlib spec
   if ((flg & 32) != 0) do return stbi__err("no preset dict","Corrupt PNG"); // preset dictionary not allowed in png
   if (cm != 8) do return stbi__err("bad compression","Corrupt PNG"); // DEFLATE required for png
   // window = 1 << (8 + cinfo)... but who cares, we fully buffer output
   return true;
}

stbi__zdefault_length := [288]u8 {
   8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8, 8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,
   8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8, 8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,
   8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8, 8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,
   8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8, 8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,
   8,8,8,8,8,8,8,8,8,8,8,8,8,8,8,8, 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,
   9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9, 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,
   9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9, 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,
   9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9, 9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,9,
   7,7,7,7,7,7,7,7,7,7,7,7,7,7,7,7, 7,7,7,7,7,7,7,7,8,8,8,8,8,8,8,8
}
stbi__zdefault_distance := [32]u8 {
   5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5
}

stbi__parse_zlib :: proc(a: ^stbi__zbuf, parse_header: bool) -> bool
{
   final, type: u32;
   if (parse_header) {
      if (!stbi__parse_zlib_header(a)) do return false;
   }
   a.num_bits = 0;
   a.code_buffer = 0;
   for {
      final = stbi__zreceive(a,1);
      type = stbi__zreceive(a,2);
      if (type == 0) {
         if (!stbi__parse_uncompressed_block(a)) do return false;
      } else if (type == 3) {
         return false;
      } else {
         if (type == 1) {
            // use fixed code lengths
            if (!stbi__zbuild_huffman(&a.z_length  , stbi__zdefault_length[:])) do return false;
            if (!stbi__zbuild_huffman(&a.z_distance, stbi__zdefault_distance[:])) do return false;
         } else {
            if (!stbi__compute_huffman_codes(a)) do return false;
         }
         if (!stbi__parse_huffman_block(a)) do return false;
      }
      if(final != 0) do break;
   }
   return true;
}

stbi__do_zlib :: proc(a: ^stbi__zbuf, obuf: ^i8, olen: int, exp, parse_header: bool) -> bool
{
   a.zout_start = obuf;
   a.zout       = obuf;
   a.zout_end   = intrinsics.ptr_offset(obuf, olen);
   a.z_expandable = exp;

   return stbi__parse_zlib(a, parse_header);
}


stbi_zlib_decode_malloc_guesssize_headerflag :: proc(buffer: ^u8, len, initial_size: int, outlen: ^int, parse_header: bool) -> ^i8
{
   a: stbi__zbuf;
   p := cast(^i8)stbi__malloc(initial_size);
   if (p == nil) do return nil;
   a.zbuffer = buffer;
   a.zbuffer_end = intrinsics.ptr_offset(buffer, len);
   if (stbi__do_zlib(&a, p, initial_size, true, parse_header)) {
      if (outlen != nil) do outlen^ = cast(int) (uintptr(a.zout) - uintptr(a.zout_start));
      return a.zout_start;
   } else {
      STBI_FREE(a.zout_start);
      return nil;
   }
}


//////////////////////////////////////////////////////////////////////////////
//
//  generic converter from built-in img_n to req_comp
//    individual types do this automatically as much as possible (e.g. jpeg
//    does all cases internally since it needs to colorspace convert anyway,
//    and it never has alpha, so very few cases ). png can automatically
//    interleave an alpha=255 channel, but falls back to this for other cases
//
//  assume data buffer is malloced, so malloc a new one and free that one
//  only failure mode is malloc failing

stbi__compute_y :: proc(r, g, b: int) -> u8
{
   return cast(u8) (((r*77) + (g*150) +  (29*b)) >> 8);
}


// stb_image uses ints pervasively, including for offset calculations.
// therefore the largest decoded image size we can support with the
// current code, even on 64-bit targets, is INT_MAX. this is not a
// significant limitation for the intended use case.
//
// we do, however, need to make sure our size calculations don't
// overflow. hence a few helper functions for size calculations that
// multiply integers together, making sure that they're non-negative
// and no overflow occurs.

// return 1 if the sum is valid, 0 on overflow.
// negative terms are considered invalid.
INT_MAX :: 0x7fffffff;
stbi__addsizes_valid :: proc(a, b: int) -> bool
{
   if (b < 0) do return false;
   // now 0 <= b <= INT_MAX, hence also
   // 0 <= INT_MAX - b <= INTMAX.
   // And "a + b <= INT_MAX" (which might overflow) is the
   // same as a <= INT_MAX - b (no overflow)
   return a <= INT_MAX - b;
}

// returns 1 if the product is valid, 0 on overflow.
// negative factors are considered invalid.
stbi__mul2sizes_valid :: proc(a, b: int) -> bool
{
   if (a < 0 || b < 0) do return false;
   if (b == 0) do return true; // mul-by-0 is always safe
   // portable way to check for no overflows in a*b
   return a <= INT_MAX/b;
}

// returns 1 if "a*b + add" has no negative terms/factors and doesn't overflow
stbi__mad2sizes_valid :: proc(a, b, add: int) -> bool
{
   return stbi__mul2sizes_valid(a, b) && stbi__addsizes_valid(a*b, add);
}

// returns 1 if "a*b*c + add" has no negative terms/factors and doesn't overflow
stbi__mad3sizes_valid :: proc(a, b, c, add: int) -> bool
{
   return stbi__mul2sizes_valid(a, b) && stbi__mul2sizes_valid(a*b, c) &&
      stbi__addsizes_valid(a*b*c, add);
}

stbi__malloc :: proc(size: int) -> rawptr {
	result, err := mem.alloc(size);
	return result;
}

// mallocs with size overflow checking
stbi__malloc_mad2 :: proc(a, b, add: int) -> rawptr
{
   if (!stbi__mad2sizes_valid(a, b, add)) do return nil;
   return stbi__malloc(a*b + add);
}

stbi__malloc_mad3 :: proc(a, b, c, add: int) -> rawptr
{
   if (!stbi__mad3sizes_valid(a, b, c, add)) do return nil;
   return stbi__malloc(a*b*c + add);
}

STBI_ASSERT :: proc(cond: bool) {
	assert(cond);
}

stbi__convert_format :: proc(data: [^]u8, img_n, req_comp: int, x, y: uint) -> [^]u8
{
   good: [^]u8;

   if (req_comp == img_n) do return data;
   STBI_ASSERT(req_comp >= 1 && req_comp <= 4);

   good = cast([^]u8) stbi__malloc_mad3(req_comp, int(x), int(y), 0);
   if (good == nil) {
      STBI_FREE(data);
      return stbi__errpuc("outofmem", "Out of memory: Converting");
   }

   for j in 0..<uint(y) {
      src  := data[j * x * uint(img_n):];
      dest := good[j * x * uint(req_comp):];

      for ii := x -1; ii >= 0; ii-=1 {

	      switch(img_n) {
	      	case 1: {
	      		switch(req_comp) {			 
			      	case 2: {
			      		dest[0]=src[0]; dest[1]=255
			      	}
			      	case 3: {
			      		dest[0], dest[1], dest[2]=src[0], src[0], src[0];
			      	}
			      	case 4: {
			      		dest[0], dest[1], dest[2]=src[0], src[0], src[0]; 
			      		dest[3]=255;
			      	}
		      	}
	      	}
	      	case 2: {
	      		switch(req_comp) {
			      	case 1: {
			      		dest[0]=src[0];
			      	}
			      	case 3: {
			      		dest[0], dest[1], dest[2]=src[0], src[0], src[0];
			      	}
			      	case 4: {
			      		dest[0], dest[1], dest[2]=src[0], src[0], src[0]; dest[3]=src[1];
			      	}
		      	}
	      	}
	      	case 3: {
	      		switch(req_comp) {
			      	case 1: {
			      		dest[0]=src[0];dest[1]=src[1];dest[2]=src[2];dest[3]=255;
			      	}
			      	case 2: {
			      		dest[0]=stbi__compute_y(cast(int)src[0],cast(int)src[1],cast(int)src[2]);
			      	}
			      	case 4: {
			      		dest[0]=stbi__compute_y(cast(int)src[0],cast(int)src[1],cast(int)src[2]); dest[1] = 255;
			      	}
		      	}
	      	}
	      	case 4: {
				switch(req_comp) {
			      	case 1: {
			      		dest[0]=stbi__compute_y(cast(int)src[0],cast(int)src[1],cast(int)src[2]);
			      	}
			      	case 2: {
			      		dest[0]=stbi__compute_y(cast(int)src[0],cast(int)src[1],cast(int)src[2]); dest[1] = src[3];
			      	}
			      	case 3: {
			      		dest[0]=src[0];dest[1]=src[1];dest[2]=src[2];
			      	}
		      	}
	      	}
	      }
	      src = intrinsics.ptr_offset(src, img_n);
	      dest = intrinsics.ptr_offset(dest, req_comp)
      } 
   }

   STBI_FREE(data);
   return good;
}