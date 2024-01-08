import {
  Controller,
  FileTypeValidator,
  MaxFileSizeValidator,
  ParseFilePipe,
  Post,
  Request,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { Express } from 'express';
import { Permissions } from '../core/decorators/permissions.decorator';
import { Permission } from '../core/schemas/apikey.schema';
import { Roles } from '../auth/decorators/roles.decorator';
import { RoleCode } from '../auth/schemas/role.schema';
import { ProtectedRequest } from '../core/http/request';

@Permissions([Permission.GENERAL])
@Controller('files')
export class FilesController {
  @Roles([RoleCode.ADMIN])
  @UseInterceptors(FileInterceptor('image'))
  @Post('upload/public/image')
  uploadPublicImage(
    @Request() request: ProtectedRequest,
    @UploadedFile(
      new ParseFilePipe({
        validators: [
          new MaxFileSizeValidator({ maxSize: 5 * 1024 * 1024 }),
          new FileTypeValidator({ fileType: /(jpe?g|png)$/i }),
        ],
      }),
    )
    file: Express.Multer.File,
  ) {
    const baseUrl = request.protocol + '://' + request.get('host');
    return `${baseUrl}/files/image/${file.filename}`;
  }
}
