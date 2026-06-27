import { Controller, Get } from '@nestjs/common';

@Controller()
export class CoreController {
  @Get('heartbeat')
  async heartbeat() {
    return 'alive';
  }
}
