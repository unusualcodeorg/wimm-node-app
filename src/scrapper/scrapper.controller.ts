import { Controller, Get, Query } from '@nestjs/common';
import { ScrapperService } from './scrapper.service';

@Controller('meta')
export class ScrapperController {
  constructor(private readonly scapperService: ScrapperService) {}

  @Get('content')
  async findContent(@Query('url') url: string) {
    return await this.scapperService.scrape(url);
  }
}
