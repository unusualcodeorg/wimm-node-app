import { Reflector } from '@nestjs/core';
import { Permission } from '../schemas/apikey.schema';

export const Permissions = Reflector.createDecorator<Permission[]>();
