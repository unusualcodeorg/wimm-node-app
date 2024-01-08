import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DiskConfig, DiskConfigName } from '../config/disk.config';
import { extname, resolve } from 'path';

@Injectable()
export class FilesService {
  constructor(private readonly configService: ConfigService) {}

  getDiskPath() {
    const diskConfig =
      this.configService.getOrThrow<DiskConfig>(DiskConfigName);
    const diskPath = resolve(__dirname, '../..', diskConfig.path);
    return diskPath;
  }

  getFileName(file: Express.Multer.File) {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1e9);
    const ext = extname(file.originalname).toLowerCase();
    const name = file.originalname.replace(/\s/g, '-').replace(ext, '');
    const fileName = `${name}_${uniqueSuffix}${ext}`;
    return fileName;
  }

  getImageCacheDuration() {
    const diskConfig =
      this.configService.getOrThrow<DiskConfig>(DiskConfigName);
    return diskConfig.imageCacheDuration;
  }
}
