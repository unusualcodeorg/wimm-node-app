import {
  Body,
  Controller,
  Get,
  NotFoundException,
  Put,
  Request,
} from '@nestjs/common';
import { UserService } from './user.service';
import { ProtectedRequest } from '../core/http/request';
import { UserDto } from './dto/user.dto';
import { UpdateProfileDto } from './dto/upadte-profile.dto';

@Controller('profile')
export class UserController {
  constructor(private readonly userService: UserService) {}
  @Get('my')
  async findMy(@Request() request: ProtectedRequest) {
    const profile = await this.userService.findPrivateProfile(request.user);
    if (!profile) throw new NotFoundException('Profile Not Found');
    return new UserDto(profile);
  }

  @Put()
  async update(
    @Request() request: ProtectedRequest,
    @Body() updateProfileDto: UpdateProfileDto,
  ) {
    return await this.userService.updateProfile(request.user, updateProfileDto);
  }
}
