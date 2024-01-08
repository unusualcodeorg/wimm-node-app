import { Injectable } from '@nestjs/common';
import { diskStorage } from 'multer';
import {
  MulterModuleOptions,
  MulterOptionsFactory,
} from '@nestjs/platform-express';
import { FilesService } from './files.service';

@Injectable()
export class FileDiskFactory implements MulterOptionsFactory {
  constructor(private readonly filesService: FilesService) {}

  createMulterOptions(): MulterModuleOptions {
    return {
      storage: diskStorage({
        destination: this.filesService.getDiskPath(),
        filename: (_, file, callback) => {
          const fileName = this.filesService.getFileName(file);
          callback(null, fileName);
        },
      }),
    };
  }
}
