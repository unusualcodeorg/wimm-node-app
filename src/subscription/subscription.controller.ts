import { Body, Controller, Post, Request } from '@nestjs/common';
import { SubscriptionService } from './subscription.service';
import { CreateSubscriptionDto } from './dto/create-subscription.dto';
import { ProtectedRequest } from '../core/http/request';

@Controller('subscription')
export class SubscriptionController {
  constructor(private readonly subscriptionService: SubscriptionService) {}

  @Post()
  async create(
    @Request() request: ProtectedRequest,
    @Body() createSubscriptionDto: CreateSubscriptionDto,
  ) {
    // await this.subscriptionService.create(request.user, createSubscriptionDto);
    return 'success';
  }
}
