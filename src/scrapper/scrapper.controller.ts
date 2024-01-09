import { Controller, Get, Query } from '@nestjs/common';
import { Permissions } from '../core/decorators/permissions.decorator';
import { Permission } from '../core/schemas/apikey.schema';
import { ScrapperService } from './scrapper.service';

@Permissions([Permission.GENERAL])
@Controller('meta')
export class ScrapperController {
  constructor(private readonly scapperService: ScrapperService) {}

  @Get('content')
  async findContent(@Query('url') url: string) {
    return await this.scapperService.scrape(url);
  }
}
